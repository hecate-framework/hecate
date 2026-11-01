/*
 * hecate.http.native: the incremental HTTP/1.1 parser of hecate.http (ADR 0019), a binding to llhttp (vendored in
 * csrc/vendor/llhttp).
 *
 * Strictness: llhttp starts with every lenient flag off, and this binding never calls an llhttp_set_lenient_*
 * function and exposes none to Lua. On top of llhttp's own rules the binding refuses what a server for HTTP does not
 * speak: versions other than HTTP/1.0 and HTTP/1.1, the RTSP and ICE protocols and their methods, and the chunked
 * transfer coding in HTTP/1.0 (RFC 9112 sections 2.3, 6.1).
 *
 * Memory ownership: the callbacks of llhttp never touch the Lua state. They record events in a log owned by the
 * parser userdata (freed by close and __gc): the spans of the content are recorded as offsets into the chunk being
 * parsed, which stays alive on the Lua stack until the events are built; the head of a message (target, reason, fields)
 * is copied into buffers of the parser, because it may span chunks. Once llhttp_execute has returned, the failure is
 * stored in the parser first, then the log is turned into Lua values (strings by copy), so no Lua reference outlives
 * a call and a Lua memory error cannot unwind through the C parser or leave a parser that is not failed.
 *
 * Bounds: the sizes of the target, of one field name or value, of the reason phrase and of the number of fields are
 * limits of the parser, and so is the raw byte budget of a "section": the bytes the parser consumes from the start of
 * a message (leading empty lines, request line or status line, fields, all whitespace included) to the end of its
 * head, from the end of one content chunk to the next chunk header (chunk-size digits, chunk extensions, trailer
 * section) and the whole trailer section each have `max_head_size` bytes. Spans are checked as they arrive; the bytes
 * of a call that carry no span (empty lines, digits) are checked when the call ends, so a single call can overshoot by
 * the size of that call's chunk, never by more. A call records at most `max_events` events and then pauses: `execute`
 * returns the offset where it stopped, and the caller feeds the rest.
 *
 * Event log, returned by `execute` and `finish` as a list of tables:
 *   { type = "head", method?, target?, status?, reason?, version, fields = { n1, v1, n2, v2, ... }, keep_alive, upgrade,
 *     chunked, content_length? }
 *   { type = "data", data }          contiguous content bytes are one event
 *   { type = "complete", trailers? = { n1, v1, ... } }
 *   { type = "upgrade", position }   the connection leaves HTTP; the bytes after `position` (0-based) are not HTTP
 *
 * A failure is a table { code, reason, position, kind? }: `kind` is set for the failures of this binding (a stable
 * identifier, never matched on text), absent for llhttp's own; `position` is the 0-based offset in the chunk of the
 * call that failed. A failed parser, and a parser after an upgrade, return the same failure to every later call.
 *
 * Sources of normative behaviour: RFC 9112 sections 2.2, 2.3, 3, 5, 6, 7.1; RFC 9110 section 5.
 */
#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "lauxlib.h"
#include "lua.h"
#include "vendor/llhttp/llhttp.h"

#define PARSER_METATABLE "hecate.http.native.parser"

/* Defaults of the limits (every limit has a safe default). The Lua wrapper documents the same values. */
#define DEFAULT_MAX_TARGET 8192
#define DEFAULT_MAX_FIELD 8192
#define DEFAULT_MAX_HEAD 65536
#define DEFAULT_MAX_FIELDS 100
#define DEFAULT_MAX_EVENTS 1024
/* The largest value an option may take: every length stays far below INT_MAX and 2^32. */
#define LIMIT_CEILING 16777216
/* Buffers that grew beyond this are released when they are empty. */
#define KEEP_CAPACITY 16384
#define KEEP_RECORDS 1024

typedef struct {
  char *data;
  size_t len;
  size_t cap;
} buffer;

enum { EV_HEAD = 1, EV_DATA, EV_COMPLETE };

/* The failures of this binding (`kind` of a failure) and the reason of each. */
enum {
  K_NONE = 0,
  K_TARGET,
  K_FIELD_NAME,
  K_FIELD_VALUE,
  K_REASON,
  K_HEAD,
  K_FIELDS,
  K_CHUNKED_10,
  K_VERSION,
  K_METHOD,
  K_PROTOCOL,
  K_MEMORY,
  K_UPGRADED,
  K_COUNT
};

static const char *const kind_name[K_COUNT] = {
    NULL,
    "target_too_long",
    "field_name_too_large",
    "field_value_too_large",
    "reason_too_long",
    "head_too_large",
    "too_many_fields",
    "chunked_in_http_1_0",
    "unsupported_version",
    "unsupported_method",
    "unsupported_protocol",
    "out_of_memory",
    "upgraded",
};

static const char *const kind_reason[K_COUNT] = {
    NULL,
    "request target too long",
    "field name too large",
    "field value too large",
    "reason phrase too long",
    "head too large",
    "too many fields",
    "chunked transfer coding in HTTP/1.0",
    "unsupported HTTP version",
    "unsupported method",
    "unsupported protocol",
    "out of memory",
    "connection upgraded",
};

typedef struct {
  int kind;
  size_t off; /* DATA: offset of the bytes in the chunk; HEAD, COMPLETE: offset of the field block in log_bytes */
  size_t len;
  size_t count; /* fields in the block */
  size_t target_off, target_len, reason_off, reason_len;
  int method, status, major, minor, keep_alive, upgrade, chunked, has_length;
  uint64_t content_length;
} record;

typedef struct {
  llhttp_t llhttp; /* first: the callbacks receive a pointer to it */
  int request;
  int skip_body;
  int closed;
  int terminal; /* failed or upgraded: the stored failure is returned by every call */
  int err_code; /* llhttp errno of the stored failure */
  int err_kind;
  const char *err_reason; /* a static string */
  size_t err_position;
  size_t max_target, max_field, max_head, max_fields, max_events;
  size_t field_count;
  /* The section budget (see the header comment). */
  const char *chunk; /* the chunk of the running call, NULL otherwise */
  size_t carry; /* raw bytes of the current section consumed by earlier calls */
  size_t origin; /* offset in the chunk where the current section starts */
  int fresh; /* a section started and no span of it has been seen */
  int boundary; /* a section boundary occurred during this call */
  size_t last_end; /* offset in the chunk of the end of the last span */
  int call_kind; /* the failure kind a callback set during this call */
  char protocol[8];
  size_t protocol_len;
  buffer target, status, field, value, block; /* the message being received */
  size_t block_count;
  buffer log_bytes; /* the copied head of the events of the current call */
  record *log;
  size_t log_len, log_cap;
} parser;

/* Buffers ------------------------------------------------------------------------------------------------------ */

static int buffer_add(buffer *b, const char *at, size_t n) {
  if (n > SIZE_MAX - b->len - 1) return -1;
  if (b->len + n > b->cap) {
    size_t cap = b->cap ? b->cap : 64;
    while (cap < b->len + n) {
      if (cap > SIZE_MAX / 2) return -1;
      cap *= 2;
    }
    char *grown = (char *)realloc(b->data, cap);
    if (grown == NULL) return -1;
    b->data = grown;
    b->cap = cap;
  }
  if (n > 0) memcpy(b->data + b->len, at, n);
  b->len += n;
  return 0;
}

static void buffer_free(buffer *b) {
  free(b->data);
  b->data = NULL;
  b->len = 0;
  b->cap = 0;
}

/* Releases an empty buffer that grew large: a parser that once saw a big head does not keep it for its lifetime. */
static void buffer_trim(buffer *b) {
  if (b->len == 0 && b->cap > KEEP_CAPACITY) buffer_free(b);
}

static void put_u32(buffer *b, size_t n, int *failed) {
  unsigned char raw[4];
  raw[0] = (unsigned char)(n & 0xff);
  raw[1] = (unsigned char)((n >> 8) & 0xff);
  raw[2] = (unsigned char)((n >> 16) & 0xff);
  raw[3] = (unsigned char)((n >> 24) & 0xff);
  if (buffer_add(b, (const char *)raw, 4) != 0) *failed = 1;
}

static size_t get_u32(const char *at) {
  const unsigned char *raw = (const unsigned char *)at;
  return (size_t)raw[0] | ((size_t)raw[1] << 8) | ((size_t)raw[2] << 16) | ((size_t)raw[3] << 24);
}

static void release(parser *p) {
  buffer_free(&p->target);
  buffer_free(&p->status);
  buffer_free(&p->field);
  buffer_free(&p->value);
  buffer_free(&p->block);
  buffer_free(&p->log_bytes);
  free(p->log);
  p->log = NULL;
  p->log_len = p->log_cap = 0;
  p->block_count = 0;
}

/* Callbacks ---------------------------------------------------------------------------------------------------- */

/* Records the failure kind and returns the code that makes llhttp stop. */
static int fail(llhttp_t *l, int kind) {
  parser *p = (parser *)l;
  p->call_kind = kind;
  llhttp_set_error_reason(l, kind_reason[kind]);
  return HPE_USER;
}

static record *new_record(parser *p, int kind) {
  if (p->log_len == p->log_cap) {
    size_t cap = p->log_cap ? p->log_cap * 2 : 8;
    record *grown = (record *)realloc(p->log, cap * sizeof(record));
    if (grown == NULL) return NULL;
    p->log = grown;
    p->log_cap = cap;
  }
  record *r = &p->log[p->log_len++];
  memset(r, 0, sizeof(*r));
  r->kind = kind;
  return r;
}

/* A section of the budget ended and the next one starts. */
static void boundary(parser *p) {
  p->boundary = 1;
  p->fresh = 1;
  p->carry = 0;
}

/* A span of the head, of a chunk header or of a trailer arrived: checks the raw budget of its section. */
static int within_budget(parser *p, const char *at, size_t n) {
  size_t end = (size_t)(at - p->chunk) + n;
  if (p->fresh) {
    p->origin = (size_t)(at - p->chunk);
    p->fresh = 0;
  }
  p->last_end = end;
  return p->carry <= p->max_head && end - p->origin <= p->max_head - p->carry;
}

static int on_message_begin(llhttp_t *l) {
  parser *p = (parser *)l;
  p->target.len = p->status.len = p->field.len = p->value.len = p->block.len = 0;
  buffer_trim(&p->target);
  buffer_trim(&p->status);
  buffer_trim(&p->field);
  buffer_trim(&p->value);
  buffer_trim(&p->block);
  p->block_count = 0;
  p->field_count = 0;
  p->protocol_len = 0;
  boundary(p);
  return 0;
}

static int on_protocol(llhttp_t *l, const char *at, size_t n) {
  parser *p = (parser *)l;
  if (!within_budget(p, at, n)) return fail(l, K_HEAD);
  if (n > sizeof(p->protocol) - p->protocol_len) return fail(l, K_PROTOCOL);
  memcpy(p->protocol + p->protocol_len, at, n);
  p->protocol_len += n;
  return 0;
}

/* llhttp also parses RTSP and ICE messages: only HTTP is spoken here. */
static int on_protocol_complete(llhttp_t *l) {
  parser *p = (parser *)l;
  int http = p->protocol_len == 4 && memcmp(p->protocol, "HTTP", 4) == 0;
  p->protocol_len = 0;
  return http ? 0 : fail(l, K_PROTOCOL);
}

static int on_span_of_the_head(llhttp_t *l, const char *at, size_t n) {
  return within_budget((parser *)l, at, n) ? 0 : fail(l, K_HEAD);
}

static int on_method_complete(llhttp_t *l) {
  int method = (int)l->method;
  /* The RTSP methods, and SOURCE (ICE), are not HTTP methods (RFC 9110 section 9). */
  if (method == (int)HTTP_SOURCE || (method >= (int)HTTP_DESCRIBE && method <= (int)HTTP_FLUSH)) {
    return fail(l, K_METHOD);
  }
  return 0;
}

static int on_version_complete(llhttp_t *l) {
  if (l->http_major != 1 || l->http_minor > 1) return fail(l, K_VERSION);
  return 0;
}

static int on_url(llhttp_t *l, const char *at, size_t n) {
  parser *p = (parser *)l;
  if (!within_budget(p, at, n)) return fail(l, K_HEAD);
  if (n > p->max_target || p->target.len > p->max_target - n) return fail(l, K_TARGET);
  return buffer_add(&p->target, at, n) == 0 ? 0 : fail(l, K_MEMORY);
}

static int on_status(llhttp_t *l, const char *at, size_t n) {
  parser *p = (parser *)l;
  if (!within_budget(p, at, n)) return fail(l, K_HEAD);
  if (n > p->max_field || p->status.len > p->max_field - n) return fail(l, K_REASON);
  return buffer_add(&p->status, at, n) == 0 ? 0 : fail(l, K_MEMORY);
}

static int on_header_field(llhttp_t *l, const char *at, size_t n) {
  parser *p = (parser *)l;
  if (!within_budget(p, at, n)) return fail(l, K_HEAD);
  /* The count is checked where a name starts. */
  if (p->field.len == 0 && n > 0) {
    if (p->field_count >= p->max_fields) return fail(l, K_FIELDS);
    p->field_count++;
  }
  if (n > p->max_field || p->field.len > p->max_field - n) return fail(l, K_FIELD_NAME);
  return buffer_add(&p->field, at, n) == 0 ? 0 : fail(l, K_MEMORY);
}

static int on_header_value(llhttp_t *l, const char *at, size_t n) {
  parser *p = (parser *)l;
  if (!within_budget(p, at, n)) return fail(l, K_HEAD);
  if (n > p->max_field || p->value.len > p->max_field - n) return fail(l, K_FIELD_VALUE);
  return buffer_add(&p->value, at, n) == 0 ? 0 : fail(l, K_MEMORY);
}

static int on_header_value_complete(llhttp_t *l) {
  parser *p = (parser *)l;
  int failed = 0;
  put_u32(&p->block, p->field.len, &failed);
  put_u32(&p->block, p->value.len, &failed);
  if (buffer_add(&p->block, p->field.data, p->field.len) != 0) failed = 1;
  if (buffer_add(&p->block, p->value.data, p->value.len) != 0) failed = 1;
  if (failed) return fail(l, K_MEMORY);
  p->block_count++;
  p->field.len = 0;
  p->value.len = 0;
  return 0;
}

/* Copies the pending field block into the log bytes and clears it. */
static int move_block(parser *p, record *r) {
  r->off = p->log_bytes.len;
  r->len = p->block.len;
  r->count = p->block_count;
  if (buffer_add(&p->log_bytes, p->block.data, p->block.len) != 0) return -1;
  p->block.len = 0;
  p->block_count = 0;
  return 0;
}

static int on_headers_complete(llhttp_t *l) {
  parser *p = (parser *)l;
  if ((l->flags & F_CHUNKED) != 0 && l->http_major == 1 && l->http_minor == 0) return fail(l, K_CHUNKED_10);
  record *r = new_record(p, EV_HEAD);
  if (r == NULL) return fail(l, K_MEMORY);
  r->major = l->http_major;
  r->minor = l->http_minor;
  r->keep_alive = llhttp_should_keep_alive(l);
  r->upgrade = l->upgrade != 0;
  r->chunked = (l->flags & F_CHUNKED) != 0;
  r->has_length = (l->flags & F_CONTENT_LENGTH) != 0;
  r->content_length = l->content_length;
  if (p->request) {
    r->method = l->method;
  } else {
    r->status = l->status_code;
    r->reason_off = p->log_bytes.len;
    r->reason_len = p->status.len;
    if (buffer_add(&p->log_bytes, p->status.data, p->status.len) != 0) return fail(l, K_MEMORY);
  }
  r->target_off = p->log_bytes.len;
  r->target_len = p->target.len;
  if (buffer_add(&p->log_bytes, p->target.data, p->target.len) != 0) return fail(l, K_MEMORY);
  if (move_block(p, r) != 0) return fail(l, K_MEMORY);
  p->field_count = 0; /* the trailers have a budget of their own */
  boundary(p);
  /* Only the final response consumes skip_body: an interim one (1xx, RFC 9110 section 15.2) is followed by it. */
  if (p->skip_body && !p->request && l->status_code >= 200) {
    p->skip_body = 0;
    return 1; /* llhttp: the message has no body (response to HEAD) */
  }
  return 0;
}

static int on_body(llhttp_t *l, const char *at, size_t n) {
  parser *p = (parser *)l;
  size_t off = (size_t)(at - p->chunk);
  record *last = p->log_len > 0 ? &p->log[p->log_len - 1] : NULL;
  boundary(p);
  if (last != NULL && last->kind == EV_DATA && last->off + last->len == off) {
    last->len += n; /* contiguous with the previous span */
    return 0;
  }
  record *r = new_record(p, EV_DATA);
  if (r == NULL) return fail(l, K_MEMORY);
  r->off = off;
  r->len = n;
  return p->log_len >= p->max_events ? HPE_PAUSED : 0;
}

static int on_chunk_extension(llhttp_t *l, const char *at, size_t n) {
  parser *p = (parser *)l;
  if (!within_budget(p, at, n)) return fail(l, K_HEAD);
  return 0;
}

static int on_chunk_header(llhttp_t *l) {
  boundary((parser *)l);
  return 0;
}

static int on_message_complete(llhttp_t *l) {
  parser *p = (parser *)l;
  record *r = new_record(p, EV_COMPLETE);
  if (r == NULL) return fail(l, K_MEMORY);
  if (move_block(p, r) != 0) return fail(l, K_MEMORY);
  boundary(p);
  return p->log_len >= p->max_events ? HPE_PAUSED : 0;
}

static const llhttp_settings_t settings = {
    .on_message_begin = on_message_begin,
    .on_protocol = on_protocol,
    .on_url = on_url,
    .on_status = on_status,
    .on_method = on_span_of_the_head,
    .on_version = on_span_of_the_head,
    .on_header_field = on_header_field,
    .on_header_value = on_header_value,
    .on_chunk_extension_name = on_chunk_extension,
    .on_chunk_extension_value = on_chunk_extension,
    .on_protocol_complete = on_protocol_complete,
    .on_method_complete = on_method_complete,
    .on_version_complete = on_version_complete,
    .on_header_value_complete = on_header_value_complete,
    .on_headers_complete = on_headers_complete,
    .on_body = on_body,
    .on_chunk_header = on_chunk_header,
    .on_message_complete = on_message_complete,
};

/* Lua side ----------------------------------------------------------------------------------------------------- */

static parser *check_parser(lua_State *L) {
  parser *p = (parser *)luaL_checkudata(L, 1, PARSER_METATABLE);
  return p;
}

static parser *open_parser(lua_State *L) {
  parser *p = check_parser(L);
  if (p->closed) luaL_error(L, "the parser is closed");
  return p;
}

static int parser_close(lua_State *L) {
  parser *p = check_parser(L);
  release(p);
  p->closed = 1;
  return 0;
}

static const char *const option_names[] = {"max_target_size", "max_field_size", "max_head_size", "max_fields",
                                           "max_events", NULL};

/* Reads the options table at `index`: integers between 1 and LIMIT_CEILING, known names only. */
static void read_options(lua_State *L, int index, parser *p) {
  size_t *targets[] = {&p->max_target, &p->max_field, &p->max_head, &p->max_fields, &p->max_events};
  lua_pushnil(L);
  while (lua_next(L, index) != 0) {
    int found = -1;
    if (lua_type(L, -2) == LUA_TSTRING) {
      const char *key = lua_tostring(L, -2);
      for (int i = 0; option_names[i] != NULL; i++) {
        if (strcmp(key, option_names[i]) == 0) found = i;
      }
    }
    if (found < 0) luaL_error(L, "unknown option %s", lua_type(L, -2) == LUA_TSTRING ? lua_tostring(L, -2) : "(not a name)");
    if (!lua_isinteger(L, -1)) luaL_error(L, "option %s must be an integer", option_names[found]);
    lua_Integer n = lua_tointeger(L, -1);
    if (n < 1 || n > LIMIT_CEILING) {
      luaL_error(L, "option %s must be between 1 and %d", option_names[found], LIMIT_CEILING);
    }
    *targets[found] = (size_t)n;
    lua_pop(L, 1);
  }
}

/* new(kind, options?): kind is "request" or "response". */
static int native_new(lua_State *L) {
  static const char *const kinds[] = {"request", "response", NULL};
  int kind = luaL_checkoption(L, 1, NULL, kinds);
  if (!lua_isnoneornil(L, 2)) luaL_checktype(L, 2, LUA_TTABLE);
  parser *p = (parser *)lua_newuserdatauv(L, sizeof(parser), 0);
  memset(p, 0, sizeof(*p));
  luaL_setmetatable(L, PARSER_METATABLE); /* from here on __gc frees whatever the parser owns */
  p->request = kind == 0;
  p->max_target = DEFAULT_MAX_TARGET;
  p->max_field = DEFAULT_MAX_FIELD;
  p->max_head = DEFAULT_MAX_HEAD;
  p->max_fields = DEFAULT_MAX_FIELDS;
  p->max_events = DEFAULT_MAX_EVENTS;
  p->fresh = 1;
  if (!lua_isnoneornil(L, 2)) read_options(L, 2, p);
  llhttp_init(&p->llhttp, p->request ? HTTP_REQUEST : HTTP_RESPONSE, &settings);
  return 1;
}

static void push_field_block(lua_State *L, const char *block, size_t count) {
  lua_createtable(L, (int)(count * 2), 0); /* count <= max_fields <= LIMIT_CEILING */
  lua_Integer index = 1;
  for (size_t i = 0; i < count; i++) {
    size_t nlen = get_u32(block), vlen = get_u32(block + 4);
    block += 8;
    lua_pushlstring(L, block, nlen);
    lua_rawseti(L, -2, index++);
    lua_pushlstring(L, block + nlen, vlen);
    lua_rawseti(L, -2, index++);
    block += nlen + vlen;
  }
}

static void push_event(lua_State *L, parser *p, const record *r) {
  const char *bytes = p->log_bytes.data;
  lua_createtable(L, 0, 8);
  switch (r->kind) {
    case EV_HEAD:
      lua_pushstring(L, "head");
      lua_setfield(L, -2, "type");
      if (p->request) {
        lua_pushstring(L, llhttp_method_name((llhttp_method_t)r->method));
        lua_setfield(L, -2, "method");
        lua_pushlstring(L, bytes + r->target_off, r->target_len);
        lua_setfield(L, -2, "target");
      } else {
        lua_pushinteger(L, r->status);
        lua_setfield(L, -2, "status");
        lua_pushlstring(L, bytes + r->reason_off, r->reason_len);
        lua_setfield(L, -2, "reason");
      }
      lua_pushfstring(L, "HTTP/%d.%d", r->major, r->minor);
      lua_setfield(L, -2, "version");
      push_field_block(L, bytes + r->off, r->count);
      lua_setfield(L, -2, "fields");
      lua_pushboolean(L, r->keep_alive);
      lua_setfield(L, -2, "keep_alive");
      lua_pushboolean(L, r->upgrade);
      lua_setfield(L, -2, "upgrade");
      lua_pushboolean(L, r->chunked);
      lua_setfield(L, -2, "chunked");
      if (r->has_length) {
        lua_pushinteger(L, r->content_length > (uint64_t)LUA_MAXINTEGER ? LUA_MAXINTEGER : (lua_Integer)r->content_length);
        lua_setfield(L, -2, "content_length");
      }
      break;
    case EV_DATA:
      lua_pushstring(L, "data");
      lua_setfield(L, -2, "type");
      lua_pushlstring(L, p->chunk + r->off, r->len);
      lua_setfield(L, -2, "data");
      break;
    default:
      lua_pushstring(L, "complete");
      lua_setfield(L, -2, "type");
      if (r->count > 0) {
        push_field_block(L, bytes + r->off, r->count);
        lua_setfield(L, -2, "trailers");
      }
      break;
  }
}

/* The offset of `pos` in the chunk, clamped to the chunk (llhttp_get_error_pos points into it after an error). */
static size_t offset_of(const char *chunk, size_t len, const char *pos) {
  if (chunk == NULL || pos == NULL) return 0;
  uintptr_t base = (uintptr_t)chunk, at = (uintptr_t)pos;
  if (at < base) return 0;
  return at - base > len ? len : (size_t)(at - base);
}

static void store_failure(parser *p, int code, int kind, const char *reason, size_t position) {
  p->terminal = 1;
  p->err_code = code;
  p->err_kind = kind;
  p->err_reason = reason;
  p->err_position = position;
}

static int push_failure(lua_State *L, const parser *p) {
  lua_createtable(L, 0, 4);
  lua_pushstring(L, llhttp_errno_name((llhttp_errno_t)p->err_code));
  lua_setfield(L, -2, "code");
  lua_pushstring(L, p->err_reason);
  lua_setfield(L, -2, "reason");
  lua_pushinteger(L, (lua_Integer)p->err_position);
  lua_setfield(L, -2, "position");
  if (p->err_kind != K_NONE) {
    lua_pushstring(L, kind_name[p->err_kind]);
    lua_setfield(L, -2, "kind");
  }
  return 1;
}

/* Pushes the events of the call (the log) as a list; `upgrade` >= 0 appends an upgrade event at that position. */
static void push_events(lua_State *L, parser *p, long long upgrade) {
  lua_createtable(L, (int)(p->log_len < (size_t)INT_MAX - 1 ? p->log_len + 1 : 0), 0);
  for (size_t i = 0; i < p->log_len; i++) {
    push_event(L, p, &p->log[i]);
    lua_rawseti(L, -2, (lua_Integer)(i + 1));
  }
  if (upgrade >= 0) {
    lua_createtable(L, 0, 2);
    lua_pushstring(L, "upgrade");
    lua_setfield(L, -2, "type");
    lua_pushinteger(L, (lua_Integer)upgrade);
    lua_setfield(L, -2, "position");
    lua_rawseti(L, -2, (lua_Integer)p->log_len + 1);
  }
}

static void start_call(parser *p, const char *chunk) {
  p->log_len = 0;
  p->log_bytes.len = 0;
  buffer_trim(&p->log_bytes);
  if (p->log_cap > KEEP_RECORDS) {
    free(p->log);
    p->log = NULL;
    p->log_cap = 0;
  }
  p->chunk = chunk;
  p->boundary = 0;
  p->call_kind = K_NONE;
  p->last_end = 0;
  if (!p->fresh) p->origin = 0;
}

/* Answers a call of a parser that already failed (or upgraded): no events, the stored failure. */
static int answer_terminal(lua_State *L, parser *p) {
  lua_createtable(L, 0, 0);
  push_failure(L, p);
  lua_pushinteger(L, 0);
  return 3;
}

/* execute(data, start?): events, failure or nil, consumed. `start` is a 0-based offset into data. A parse that stops
 * early (event cap) returns the offset where it stopped as `consumed`; call again from there. */
static int parser_execute(lua_State *L) {
  parser *p = open_parser(L);
  size_t len;
  const char *data = luaL_checklstring(L, 2, &len);
  lua_Integer start = luaL_optinteger(L, 3, 0);
  luaL_argcheck(L, start >= 0 && (lua_Unsigned)start <= len, 3, "start out of range");
  if (p->terminal) return answer_terminal(L, p);
  const char *chunk = data + start;
  size_t chunk_len = len - (size_t)start;
  start_call(p, chunk);
  llhttp_errno_t err = llhttp_execute(&p->llhttp, chunk, chunk_len);
  size_t offset = err == HPE_OK ? chunk_len : offset_of(chunk, chunk_len, llhttp_get_error_pos(&p->llhttp));
  size_t base = (size_t)start;
  long long upgrade = -1;
  size_t consumed = len;
  if (err == HPE_PAUSED) {
    llhttp_resume(&p->llhttp);
    consumed = base + offset;
    err = HPE_OK;
  }
  if (err == HPE_OK) {
    /* The raw budget of the section still open: counted from its first span, or from the start of the call. */
    if (p->boundary) {
      p->carry = p->fresh ? 0 : (offset > p->origin ? offset - p->origin : 0);
    } else {
      p->carry = p->carry > SIZE_MAX - offset ? SIZE_MAX : p->carry + offset;
    }
    if (p->carry > p->max_head) {
      store_failure(p, HPE_USER, K_HEAD, kind_reason[K_HEAD], base + offset);
      err = HPE_USER;
    }
  } else if (err == HPE_PAUSED_UPGRADE) {
    upgrade = (long long)(base + offset);
    store_failure(p, HPE_PAUSED_UPGRADE, K_UPGRADED, kind_reason[K_UPGRADED], base + offset);
  } else {
    int kind = p->call_kind;
    const char *reason = kind != K_NONE ? kind_reason[kind] : llhttp_get_error_reason(&p->llhttp);
    store_failure(p, (int)err, kind, reason != NULL ? reason : "parse error", base + offset);
  }
  /* The failure is stored above: from here on the Lua allocations below may raise without leaving a live parser. */
  push_events(L, p, upgrade);
  if (err == HPE_OK || err == HPE_PAUSED_UPGRADE) {
    lua_pushnil(L);
  } else {
    push_failure(L, p);
  }
  p->chunk = NULL;
  lua_pushinteger(L, (lua_Integer)consumed);
  return 3;
}

/* finish(): tells the parser that the connection ended: events, failure (an incomplete message), 0. */
static int parser_finish(lua_State *L) {
  parser *p = open_parser(L);
  if (p->terminal) return answer_terminal(L, p);
  start_call(p, NULL);
  llhttp_errno_t err = llhttp_finish(&p->llhttp);
  if (err != HPE_OK) {
    const char *reason = llhttp_get_error_reason(&p->llhttp);
    store_failure(p, (int)err, p->call_kind, p->call_kind != K_NONE ? kind_reason[p->call_kind] : reason != NULL ? reason : "parse error", 0);
  }
  push_events(L, p, -1);
  if (err == HPE_OK) {
    lua_pushnil(L);
  } else {
    push_failure(L, p);
  }
  lua_pushinteger(L, 0);
  return 3;
}

/* skip_body(): the final response that follows has no body (the response to a HEAD request, RFC 9112 section 6.3);
 * an interim response (1xx) does not consume it. For a parser of responses only. */
static int parser_skip_body(lua_State *L) {
  parser *p = open_parser(L);
  if (p->request) return luaL_error(L, "skip_body is for a parser of responses");
  p->skip_body = 1;
  return 0;
}

#if defined(_WIN32)
#define HECATE_EXPORT __declspec(dllexport)
#elif defined(__GNUC__)
#define HECATE_EXPORT __attribute__((visibility("default")))
#else
#define HECATE_EXPORT
#endif

HECATE_EXPORT int luaopen_hecate_http_native(lua_State *L) {
  static const luaL_Reg methods[] = {
      {"execute", parser_execute}, {"finish", parser_finish}, {"skip_body", parser_skip_body}, {"close", parser_close},
      {NULL, NULL}};
  static const luaL_Reg meta[] = {{"__gc", parser_close}, {"__close", parser_close}, {NULL, NULL}};
  if (luaL_newmetatable(L, PARSER_METATABLE)) {
    luaL_setfuncs(L, meta, 0);
    luaL_newlibtable(L, methods);
    luaL_setfuncs(L, methods, 0);
    lua_setfield(L, -2, "__index");
    lua_pushstring(L, PARSER_METATABLE);
    lua_setfield(L, -2, "__metatable");
  }
  lua_pop(L, 1);
  lua_createtable(L, 0, 1);
  lua_pushcfunction(L, native_new);
  lua_setfield(L, -2, "new");
  return 1;
}
