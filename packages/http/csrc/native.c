/*
 * hecate.http.native: the incremental HTTP/1.1 parser of hecate.http (ADR 0019), a binding to llhttp (vendored in
 * csrc/vendor/llhttp, strict mode: no lenient flag is ever set and none is reachable from Lua).
 *
 * Memory ownership: the callbacks of llhttp never touch the Lua state. They copy the bytes they receive into buffers
 * owned by the parser userdata (freed by __gc) and record events in a log. Once llhttp_execute has returned, the log is
 * turned into Lua values (strings are created by copy), so no Lua reference outlives a call and a Lua memory error can
 * never unwind through the C parser. The buffers that hold a message while it is being received are bounded by the
 * limits below, which fail the parse (HPE_USER with a reason) when exceeded: an unterminated line cannot grow memory.
 *
 * Event log, returned by `execute` and `finish` as a list of tables:
 *   { type = "head", method?, target?, status?, reason?, version, fields = { n1, v1, n2, v2, ... }, keep_alive, upgrade,
 *     chunked, content_length? }
 *   { type = "data", data }
 *   { type = "complete", trailers? = { n1, v1, ... } }
 *   { type = "upgrade", position }    the connection leaves HTTP; the bytes after `position` (0-based) are not HTTP
 *
 * Sources of normative behaviour: RFC 9112 sections 2.2, 3, 5, 6 and 7.1; RFC 9110 section 5.
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
/* The largest value an option may take: keeps every length below 2^31 so that they fit the 32-bit length prefixes. */
#define LIMIT_CEILING 1073741824

typedef struct {
  char *data;
  size_t len;
  size_t cap;
} buffer;

enum { EV_HEAD = 1, EV_DATA, EV_COMPLETE };

typedef struct {
  int kind;
  size_t off; /* DATA: the bytes; HEAD, COMPLETE: the field block */
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
  int failed_memory;
  size_t max_target, max_field, max_head, max_fields;
  size_t head_size, field_count;
  buffer target, status, field, value, block; /* the message being received */
  size_t block_count;
  buffer log_bytes; /* the bytes of the events of the current call */
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

/* Callbacks ---------------------------------------------------------------------------------------------------- */

static int refuse(llhttp_t *l, const char *reason) {
  llhttp_set_error_reason(l, reason);
  return HPE_USER;
}

static int no_memory(llhttp_t *l) {
  ((parser *)l)->failed_memory = 1;
  return refuse(l, "out of memory");
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

static int on_message_begin(llhttp_t *l) {
  parser *p = (parser *)l;
  p->target.len = p->status.len = p->field.len = p->value.len = p->block.len = 0;
  p->block_count = 0;
  p->head_size = 0;
  p->field_count = 0;
  return 0;
}

static int on_url(llhttp_t *l, const char *at, size_t n) {
  parser *p = (parser *)l;
  if (n > p->max_target || p->target.len > p->max_target - n) return refuse(l, "request target too long");
  return buffer_add(&p->target, at, n) == 0 ? 0 : no_memory(l);
}

static int on_status(llhttp_t *l, const char *at, size_t n) {
  parser *p = (parser *)l;
  if (n > p->max_field || p->status.len > p->max_field - n) return refuse(l, "reason phrase too long");
  return buffer_add(&p->status, at, n) == 0 ? 0 : no_memory(l);
}

/* A piece of a field name or value: counts against the size of the field and of the whole head. */
static int account(parser *p, buffer *b, const char *at, size_t n, int *error) {
  if (n > p->max_field || b->len > p->max_field - n) {
    *error = 1;
    return -1;
  }
  if (n > p->max_head || p->head_size > p->max_head - n) {
    *error = 2;
    return -1;
  }
  p->head_size += n;
  return buffer_add(b, at, n);
}

static int on_header_field(llhttp_t *l, const char *at, size_t n) {
  parser *p = (parser *)l;
  int error = 0;
  /* The count is checked where a name starts, in a span callback: llhttp replaces the reason of a failing "complete"
   * callback by its own generic one. */
  if (p->field.len == 0 && n > 0) {
    if (p->field_count >= p->max_fields) return refuse(l, "too many fields");
    p->field_count++;
  }
  if (account(p, &p->field, at, n, &error) == 0) return 0;
  if (error == 1) return refuse(l, "field name too large");
  if (error == 2) return refuse(l, "header section too large");
  return no_memory(l);
}

static int on_header_value(llhttp_t *l, const char *at, size_t n) {
  parser *p = (parser *)l;
  int error = 0;
  if (account(p, &p->value, at, n, &error) == 0) return 0;
  if (error == 1) return refuse(l, "field value too large");
  if (error == 2) return refuse(l, "header section too large");
  return no_memory(l);
}

static int on_header_value_complete(llhttp_t *l) {
  parser *p = (parser *)l;
  int failed = 0;
  put_u32(&p->block, p->field.len, &failed);
  put_u32(&p->block, p->value.len, &failed);
  if (buffer_add(&p->block, p->field.data, p->field.len) != 0) failed = 1;
  if (buffer_add(&p->block, p->value.data, p->value.len) != 0) failed = 1;
  if (failed) return no_memory(l);
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
  record *r = new_record(p, EV_HEAD);
  if (r == NULL) return no_memory(l);
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
    if (buffer_add(&p->log_bytes, p->status.data, p->status.len) != 0) return no_memory(l);
  }
  r->target_off = p->log_bytes.len;
  r->target_len = p->target.len;
  if (buffer_add(&p->log_bytes, p->target.data, p->target.len) != 0) return no_memory(l);
  if (move_block(p, r) != 0) return no_memory(l);
  p->head_size = 0; /* the trailers have a budget of their own */
  p->field_count = 0;
  if (p->skip_body) {
    p->skip_body = 0;
    return 1; /* llhttp: the message has no body (response to HEAD) */
  }
  return 0;
}

static int on_body(llhttp_t *l, const char *at, size_t n) {
  parser *p = (parser *)l;
  record *r = new_record(p, EV_DATA);
  if (r == NULL) return no_memory(l);
  r->off = p->log_bytes.len;
  r->len = n;
  return buffer_add(&p->log_bytes, at, n) == 0 ? 0 : no_memory(l);
}

static int on_message_complete(llhttp_t *l) {
  parser *p = (parser *)l;
  record *r = new_record(p, EV_COMPLETE);
  if (r == NULL) return no_memory(l);
  return move_block(p, r) == 0 ? 0 : no_memory(l);
}

static llhttp_settings_t settings;

static void init_settings(void) {
  llhttp_settings_init(&settings);
  settings.on_message_begin = on_message_begin;
  settings.on_url = on_url;
  settings.on_status = on_status;
  settings.on_header_field = on_header_field;
  settings.on_header_value = on_header_value;
  settings.on_header_value_complete = on_header_value_complete;
  settings.on_headers_complete = on_headers_complete;
  settings.on_body = on_body;
  settings.on_message_complete = on_message_complete;
}

/* Lua side ----------------------------------------------------------------------------------------------------- */

static parser *check_parser(lua_State *L) { return (parser *)luaL_checkudata(L, 1, PARSER_METATABLE); }

static int parser_gc(lua_State *L) {
  parser *p = check_parser(L);
  buffer_free(&p->target);
  buffer_free(&p->status);
  buffer_free(&p->field);
  buffer_free(&p->value);
  buffer_free(&p->block);
  buffer_free(&p->log_bytes);
  free(p->log);
  p->log = NULL;
  p->log_len = p->log_cap = 0;
  return 0;
}

static size_t limit_option(lua_State *L, int index, const char *name, size_t fallback) {
  size_t value = fallback;
  if (lua_getfield(L, index, name) != LUA_TNIL) {
    int isint = 0;
    lua_Integer n = lua_tointegerx(L, -1, &isint);
    if (!isint || n < 1 || n > LIMIT_CEILING) {
      return (size_t)luaL_error(L, "option %s must be an integer between 1 and %d", name, LIMIT_CEILING);
    }
    value = (size_t)n;
  }
  lua_pop(L, 1);
  return value;
}

/* new(kind, options?): kind is "request" or "response". */
static int native_new(lua_State *L) {
  static const char *const kinds[] = {"request", "response", NULL};
  int kind = luaL_checkoption(L, 1, NULL, kinds);
  size_t max_target = DEFAULT_MAX_TARGET, max_field = DEFAULT_MAX_FIELD, max_head = DEFAULT_MAX_HEAD;
  size_t max_fields = DEFAULT_MAX_FIELDS;
  if (!lua_isnoneornil(L, 2)) {
    luaL_checktype(L, 2, LUA_TTABLE);
    max_target = limit_option(L, 2, "max_target_size", max_target);
    max_field = limit_option(L, 2, "max_field_size", max_field);
    max_head = limit_option(L, 2, "max_head_size", max_head);
    max_fields = limit_option(L, 2, "max_fields", max_fields);
  }
  parser *p = (parser *)lua_newuserdatauv(L, sizeof(parser), 0);
  memset(p, 0, sizeof(*p));
  luaL_setmetatable(L, PARSER_METATABLE); /* from here on __gc frees whatever the parser owns */
  p->request = kind == 0;
  p->max_target = max_target;
  p->max_field = max_field;
  p->max_head = max_head;
  p->max_fields = max_fields;
  /* HTTP_REQUEST and HTTP_RESPONSE: strict mode is llhttp's default and no llhttp_set_lenient_* is ever called. */
  llhttp_init(&p->llhttp, p->request ? HTTP_REQUEST : HTTP_RESPONSE, &settings);
  return 1;
}

static void push_field_block(lua_State *L, const char *block, size_t count) {
  lua_createtable(L, (int)(count * 2), 0);
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
      lua_pushlstring(L, bytes + r->off, r->len);
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

/* Pushes the events of the call, then the failure (a table) or nil. `data` is the chunk just parsed (or NULL). */
static int finish_call(lua_State *L, parser *p, llhttp_errno_t err, const char *data) {
  lua_createtable(L, (int)p->log_len + 1, 0);
  for (size_t i = 0; i < p->log_len; i++) {
    push_event(L, p, &p->log[i]);
    lua_rawseti(L, -2, (lua_Integer)(i + 1));
  }
  if (err == HPE_PAUSED_UPGRADE) {
    lua_createtable(L, 0, 2);
    lua_pushstring(L, "upgrade");
    lua_setfield(L, -2, "type");
    const char *pos = llhttp_get_error_pos(&p->llhttp);
    lua_pushinteger(L, data != NULL && pos != NULL ? (lua_Integer)(pos - data) : 0);
    lua_setfield(L, -2, "position");
    lua_rawseti(L, -2, (lua_Integer)p->log_len + 1);
    lua_pushnil(L);
    return 2;
  }
  if (err == HPE_OK) {
    lua_pushnil(L);
    return 2;
  }
  lua_createtable(L, 0, 4);
  lua_pushstring(L, llhttp_errno_name(err));
  lua_setfield(L, -2, "code");
  const char *reason = llhttp_get_error_reason(&p->llhttp);
  lua_pushstring(L, reason != NULL ? reason : "parse error");
  lua_setfield(L, -2, "reason");
  const char *pos = llhttp_get_error_pos(&p->llhttp);
  lua_pushinteger(L, data != NULL && pos != NULL && pos >= data ? (lua_Integer)(pos - data) : 0);
  lua_setfield(L, -2, "position");
  lua_pushboolean(L, p->failed_memory);
  lua_setfield(L, -2, "out_of_memory");
  return 2;
}

/* execute(data): events, failure. */
static int parser_execute(lua_State *L) {
  parser *p = check_parser(L);
  size_t len;
  const char *data = luaL_checklstring(L, 2, &len);
  p->log_len = 0;
  p->log_bytes.len = 0;
  llhttp_errno_t err = llhttp_execute(&p->llhttp, data, len);
  return finish_call(L, p, err, data);
}

/* finish(): tells the parser that the connection ended: events, failure (an incomplete message). */
static int parser_finish(lua_State *L) {
  parser *p = check_parser(L);
  p->log_len = 0;
  p->log_bytes.len = 0;
  llhttp_errno_t err = llhttp_finish(&p->llhttp);
  return finish_call(L, p, err, NULL);
}

/* skip_body(): the next message head ends its message (the response to a HEAD request, RFC 9112 section 6.3). */
static int parser_skip_body(lua_State *L) {
  check_parser(L)->skip_body = 1;
  return 0;
}

#if defined(_WIN32)
#define HECATE_EXPORT __declspec(dllexport)
#else
#define HECATE_EXPORT
#endif

HECATE_EXPORT int luaopen_hecate_http_native(lua_State *L) {
  static const luaL_Reg methods[] = {
      {"execute", parser_execute}, {"finish", parser_finish}, {"skip_body", parser_skip_body}, {"__gc", parser_gc},
      {NULL, NULL}};
  init_settings();
  if (luaL_newmetatable(L, PARSER_METATABLE)) {
    luaL_setfuncs(L, methods, 0);
    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");
  }
  lua_pop(L, 1);
  lua_createtable(L, 0, 1);
  lua_pushcfunction(L, native_new);
  lua_setfield(L, -2, "new");
  return 1;
}
