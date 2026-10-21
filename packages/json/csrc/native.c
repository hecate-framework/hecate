/*
 * hecate.json.native: the native backend of hecate.json (ADR 0020).
 *
 * Decoder: a binding to yyjson (vendored in csrc/vendor, RFC 8259 strict reader, UTF-8 validated).
 * The binding turns the yyjson document into the value model of hecate.json (the `null` value and the
 * array/object metatables of hecate.json.internal.markers, integer/float fidelity).
 *
 * Failures: this module reports a failure exactly as the reference backend does (reason, message,
 * offset), by delegating to it on the failure path only. When yyjson rejects the text, or when the
 * text is one the reference backend rejects and yyjson accepts (a duplicate member name, a nesting
 * deeper than max_depth, a text beyond max_size, a byte order mark, "-0", a number that does not fit a
 * 64-bit float), the binding calls hecate.json.internal.reference.decode on the same text and returns its
 * answer: a failure, or (when yyjson was stricter than the reference) the reference value. A valid text
 * never pays for this. The classification is thus deterministic and identical by construction.
 *
 * Encoder: not native yet (serde_json, ADR 0021). `encode` delegates to the reference backend.
 *
 * Sources of normative behaviour: RFC 8259 sections 2 to 8, I-JSON (RFC 7493) sections 2.1 to 2.3.
 */
#include <limits.h>
#include <stdio.h>
#include <math.h>
#include <string.h>

#include "lauxlib.h"
#include "lua.h"
#include "vendor/yyjson.h"

#define REFERENCE_MODULE "hecate.json.internal.reference"
#define MARKERS_MODULE "hecate.json.internal.markers"
#define STATE_METATABLE "hecate.json.native.state"

/* The deepest nesting the converter recurses into, whatever max_depth says: the C stack is finite (1 MiB for the main
 * thread of a Windows process, 80 to 150 bytes a level). It equals the highest max_depth the public module accepts
 * (1000, for decode and encode alike); a caller of this module that passes more is answered by the reference decoder. */
#define HARD_DEPTH_CEILING 1000

/* The registry references held by this module (one state per Lua state; freed by __gc). */
typedef struct {
  int null_ref;
  int array_ref;
  int object_ref;
  int decode_ref; /* reference.decode */
  int encode_ref; /* reference.encode */
} hecate_json_state;

static void release(lua_State *L, int *ref) {
  if (*ref != LUA_NOREF) {
    luaL_unref(L, LUA_REGISTRYINDEX, *ref);
    *ref = LUA_NOREF;
  }
}

static int state_gc(lua_State *L) {
  hecate_json_state *state = (hecate_json_state *)luaL_checkudata(L, 1, STATE_METATABLE);
  release(L, &state->null_ref);
  release(L, &state->array_ref);
  release(L, &state->object_ref);
  release(L, &state->decode_ref);
  release(L, &state->encode_ref);
  return 0;
}

static hecate_json_state *get_state(lua_State *L) {
  return (hecate_json_state *)lua_touserdata(L, lua_upvalueindex(1));
}

/* Stores the value on top of the stack in *ref (replacing the previous reference), and pops it. */
static void keep(lua_State *L, int *ref) {
  release(L, ref);
  *ref = luaL_ref(L, LUA_REGISTRYINDEX);
}

/* bind(markers): keeps the `null` value and the array/object metatables of the Lua side. */
static int native_bind(lua_State *L) {
  hecate_json_state *state = get_state(L);
  luaL_checktype(L, 1, LUA_TTABLE);
  lua_getfield(L, 1, "null");
  luaL_argcheck(L, !lua_isnil(L, -1), 1, "markers.null is missing");
  keep(L, &state->null_ref);
  lua_getfield(L, 1, "array_metatable");
  luaL_argcheck(L, lua_istable(L, -1), 1, "markers.array_metatable is missing");
  keep(L, &state->array_ref);
  lua_getfield(L, 1, "object_metatable");
  luaL_argcheck(L, lua_istable(L, -1), 1, "markers.object_metatable is missing");
  keep(L, &state->object_ref);
  return 0;
}

/* Calls a reference function (kept in the registry) with the arguments 1..nargs; returns all its results. */
static int delegate(lua_State *L, int ref, int nargs) {
  int base = lua_gettop(L);
  lua_rawgeti(L, LUA_REGISTRYINDEX, ref);
  for (int i = 1; i <= nargs; i++) lua_pushvalue(L, i);
  lua_call(L, nargs, LUA_MULTRET);
  return lua_gettop(L) - base;
}

/* encode(value, options): not native yet; the reference backend encodes (serde_json comes with ADR 0021). */
static int native_encode(lua_State *L) {
  return delegate(L, get_state(L)->encode_ref, lua_gettop(L));
}

typedef struct {
  hecate_json_state *state;
  yyjson_val *root;
  lua_Integer max_depth;
  yyjson_val *duplicate; /* set when a member name occurs twice in an object: the name (yyjson gives no position) */
} conversion;

static void mark(lua_State *L, int ref) {
  lua_rawgeti(L, LUA_REGISTRYINDEX, ref);
  lua_setmetatable(L, -2);
}

/*
 * Pushes the Lua value of `val`. Returns 0 when the conversion stops: a duplicate member name (`c->duplicate` is
 * set, the failure is ours), or a value the reference backend must decide ("-0", a float outside the 64-bit range,
 * nesting beyond the ceiling); nothing is left on the stack. `depth` is the nesting level of the containers around
 * `val`.
 */
static int convert(lua_State *L, conversion *c, yyjson_val *val, lua_Integer depth) {
  switch (yyjson_get_type(val)) {
    case YYJSON_TYPE_NULL:
      lua_rawgeti(L, LUA_REGISTRYINDEX, c->state->null_ref);
      return 1;
    case YYJSON_TYPE_BOOL:
      lua_pushboolean(L, yyjson_get_bool(val));
      return 1;
    case YYJSON_TYPE_STR:
      lua_pushlstring(L, yyjson_get_str(val), yyjson_get_len(val));
      return 1;
    case YYJSON_TYPE_NUM:
      switch (yyjson_get_subtype(val)) {
        case YYJSON_SUBTYPE_SINT:
          lua_pushinteger(L, (lua_Integer)yyjson_get_sint(val));
          return 1;
        case YYJSON_SUBTYPE_UINT: {
          /* yyjson reads every non-negative integer literal as unsigned. Up to 2^63 - 1 it is a Lua integer;
           * beyond (and within 2^64 - 1) an integer that does not fit a Lua integer decodes as a float. */
          uint64_t unsigned_value = yyjson_get_uint(val);
          if (unsigned_value <= (uint64_t)LUA_MAXINTEGER) lua_pushinteger(L, (lua_Integer)unsigned_value);
          else lua_pushnumber(L, (lua_Number)unsigned_value);
          return 1;
        }
        default: {
          double number = yyjson_get_real(val);
          /* Negative zero: "-0" is an integer literal (decodes as 0) but "-0.0" is a float that keeps its
           * sign; yyjson does not tell them apart, so the reference backend decides. */
          if (number == 0.0 && signbit(number)) return 0;
          if (isinf(number) || isnan(number)) return 0;
          lua_pushnumber(L, (lua_Number)number);
          return 1;
        }
      }
    case YYJSON_TYPE_ARR: {
      lua_Integer level = depth + 1;
      if (level > c->max_depth || level > HARD_DEPTH_CEILING) return 0;
      luaL_checkstack(L, 4, "JSON nesting too deep");
      size_t length = yyjson_arr_size(val);
      lua_createtable(L, length > (size_t)INT_MAX ? INT_MAX : (int)length, 0);
      mark(L, c->state->array_ref);
      lua_Integer index = 1;
      size_t i, max;
      yyjson_val *element;
      yyjson_arr_foreach(val, i, max, element) {
        if (!convert(L, c, element, level)) return 0;
        lua_rawseti(L, -2, index++);
      }
      return 1;
    }
    case YYJSON_TYPE_OBJ: {
      lua_Integer level = depth + 1;
      if (level > c->max_depth || level > HARD_DEPTH_CEILING) return 0;
      luaL_checkstack(L, 5, "JSON nesting too deep");
      size_t length = yyjson_obj_size(val);
      lua_createtable(L, 0, length > (size_t)INT_MAX ? INT_MAX : (int)length);
      mark(L, c->state->object_ref);
      size_t i, max;
      yyjson_val *key, *member;
      yyjson_obj_foreach(val, i, max, key, member) {
        lua_pushlstring(L, yyjson_get_str(key), yyjson_get_len(key));
        lua_pushvalue(L, -1);
        lua_rawget(L, -3);
        /* RFC 7493 section 2.3: a duplicate member name is rejected. yyjson keeps no position for it. */
        if (!lua_isnil(L, -1)) {
          c->duplicate = key;
          return 0;
        }
        lua_pop(L, 1);
        if (!convert(L, c, member, level)) return 0;
        lua_rawset(L, -3);
      }
      return 1;
    }
    default:
      return 0;
  }
}

/* Protected conversion: pushes the value, or nothing (fallback). Arg 1: light userdata `conversion`. */
static int convert_protected(lua_State *L) {
  conversion *c = (conversion *)lua_touserdata(L, 1);
  lua_settop(L, 0);
  if (!convert(L, c, c->root, 0)) {
    lua_settop(L, 0);
    lua_pushnil(L);
  }
  return 1;
}

/* The failures of decode: nil and a table { reason, message, offset } (no offset when yyjson gives none). */
#define EXCERPT_LIMIT 40

/* Pushes at most EXCERPT_LIMIT bytes of `text` quoted, cut on a character boundary, with control characters,
 * quotes and backslashes escaped (the same rule as the reference decoder: no raw input in a message). */
static void push_excerpt(lua_State *L, const char *text, size_t length) {
  int cut = length > EXCERPT_LIMIT;
  size_t stop = cut ? EXCERPT_LIMIT : length;
  while (cut && stop > 0 && ((unsigned char)text[stop] & 0xC0) == 0x80) stop--; /* not inside a UTF-8 sequence */
  luaL_Buffer buffer;
  luaL_buffinit(L, &buffer);
  luaL_addchar(&buffer, '"');
  for (size_t i = 0; i < stop; i++) {
    unsigned char c = (unsigned char)text[i];
    if (c < 32 || c == '"' || c == '\\' || c == 127) {
      char escape[8];
      snprintf(escape, sizeof escape, "\\x%02x", c);
      luaL_addstring(&buffer, escape);
    } else {
      luaL_addchar(&buffer, (char)c);
    }
  }
  luaL_addchar(&buffer, '"');
  if (cut) luaL_addstring(&buffer, " (cut)");
  luaL_pushresult(&buffer);
}

/* Pushes nil and the failure table; `offset` < 0 means "no position". The message is on top of the stack. */
static int push_failure(lua_State *L, const char *reason, lua_Integer offset) {
  lua_pushnil(L);
  lua_createtable(L, 0, 3);
  lua_pushstring(L, reason);
  lua_setfield(L, -2, "reason");
  lua_pushvalue(L, -3);
  lua_setfield(L, -2, "message");
  if (offset >= 0) {
    lua_pushinteger(L, offset);
    lua_setfield(L, -2, "offset");
  }
  lua_remove(L, -3); /* the message */
  return 2;
}

static int fail_with(lua_State *L, const char *reason, lua_Integer offset, const char *message) {
  lua_pushstring(L, message);
  return push_failure(L, reason, offset);
}

/* What the byte at `position` is, as the reference decoder says it: "character 'x'", "control character 0x0a", ... */
static void push_describe(lua_State *L, const char *text, size_t length, size_t position) {
  char description[48];
  if (position >= length) {
    lua_pushstring(L, "end of input");
    return;
  }
  unsigned char c = (unsigned char)text[position];
  if (c < 32 || c == 127) snprintf(description, sizeof description, "control character 0x%02x", c);
  else if (c < 128) snprintf(description, sizeof description, "character '%c'", c);
  else snprintf(description, sizeof description, "byte 0x%02x", c);
  lua_pushstring(L, description);
}

/* The offset of the first bracket that nests deeper than max_depth, or -1. One pass, no allocation: yyjson has no
 * depth limit and allocates for every bracket, so the text is refused before it runs. */
static lua_Integer first_too_deep(const char *text, size_t length, lua_Integer max_depth) {
  lua_Integer depth = 0;
  int in_string = 0;
  for (size_t i = 0; i < length; i++) {
    char c = text[i];
    if (in_string) {
      if (c == '\\') i++;
      else if (c == '"') in_string = 0;
    } else if (c == '"') {
      in_string = 1;
    } else if (c == '[' || c == '{') {
      if (++depth > max_depth) return (lua_Integer)i;
    } else if ((c == ']' || c == '}') && depth > 0) {
      depth--;
    }
  }
  return -1;
}

/* Whether the text ends inside a string (an unterminated string, as yyjson reports it as an unexpected end). */
static int ends_in_string(const char *text, size_t length) {
  int in_string = 0;
  for (size_t i = 0; i < length; i++) {
    if (in_string) {
      if (text[i] == '\\') i++;
      else if (text[i] == '"') in_string = 0;
    } else if (text[i] == '"') {
      in_string = 1;
    }
  }
  return in_string;
}

/* A failure of yyjson, put in the vocabulary of the codec (reason, message, offset). What yyjson cannot say (what
 * was expected, which of several defects) is not guessed: the message says what yyjson found. */
static int classify(lua_State *L, const char *text, size_t length, const yyjson_read_err *err) {
  size_t pos = err->pos;
  const char *msg = err->msg;
  switch (err->code) {
    case YYJSON_READ_ERROR_EMPTY_CONTENT:
    case YYJSON_READ_ERROR_UNEXPECTED_END: {
      /* A text cut inside a literal (`[1,tru`): the reference decoder points at the first letter of the literal. */
      if (ends_in_string(text, length))
        return fail_with(L, "syntax", (lua_Integer)length, "unterminated string: expected a closing quote");
      size_t start = length;
      while (start > 0 && text[start - 1] >= 'a' && text[start - 1] <= 'z') start--;
      size_t word = length - start;
      if (word > 0 && ((word < 4 && strncmp("true", text + start, word) == 0) ||
                       (word < 5 && strncmp("false", text + start, word) == 0) ||
                       (word < 4 && strncmp("null", text + start, word) == 0))) {
        push_describe(L, text, length, start);
        lua_pushfstring(L, "unexpected %s", lua_tostring(L, -1));
        lua_remove(L, -2);
        return push_failure(L, "syntax", (lua_Integer)start);
      }
      return fail_with(L, "syntax", (lua_Integer)length, "unexpected end of input");
    }
    case YYJSON_READ_ERROR_INVALID_NUMBER:
      if (strstr(msg, "infinity") != NULL || strstr(msg, "nan or inf") != NULL) {
        size_t end = pos;
        while (end < length && strchr("+-0123456789.eE", text[end]) != NULL) end++;
        lua_pushstring(L, "number ");
        push_excerpt(L, text + pos, end - pos);
        lua_pushstring(L, " is out of range: it does not fit in a 64-bit float (about 1.8e308 at most); RFC 8259 allows it "
                          "but parsers disagree on the result (infinity, error or clamp), so it is rejected");
        lua_concat(L, 3);
        return push_failure(L, "number_out_of_range", (lua_Integer)pos);
      }
      lua_pushfstring(L, "invalid number: %s", msg);
      /* A leading zero: yyjson points at the zero, the reference decoder at the digit after it. */
      if (strstr(msg, "leading zero") != NULL && pos + 1 < length) pos++;
      return push_failure(L, "syntax", (lua_Integer)pos);
    case YYJSON_READ_ERROR_INVALID_STRING:
      if (strstr(msg, "utf-8") != NULL || strstr(msg, "UTF-8") != NULL)
        return fail_with(L, "invalid_utf8", (lua_Integer)pos, "invalid UTF-8 in string");
      if (strstr(msg, "control character") != NULL) {
        push_describe(L, text, length, pos);
        lua_pushfstring(L, "unescaped %s in string", lua_tostring(L, -1));
        lua_remove(L, -2);
        return push_failure(L, "control_character", (lua_Integer)pos);
      }
      if (strstr(msg, "surrogate") != NULL) {
        /* The reference decoder points at the backslash of the lone escape; yyjson at the byte after it. */
        if (pos >= 6 && text[pos - 6] == '\\' && text[pos - 5] == 'u' && strstr(msg, "no low") != NULL) pos -= 6;
        else if (pos >= 6 && text[pos - 6] == '\\' && text[pos - 5] == 'u' && strstr(msg, "invalid low") != NULL) pos -= 6;
        return fail_with(L, "lone_surrogate", (lua_Integer)pos,
                         "lone surrogate escape: a \\uD800-\\uDBFF escape must be followed at once by a \\uDC00-\\uDFFF "
                         "escape, and a \\uDC00-\\uDFFF escape must follow a \\uD800-\\uDBFF escape");
      }
      if (strstr(msg, "unclosed") != NULL)
        return fail_with(L, "syntax", (lua_Integer)length, "unterminated string: expected a closing quote");
      /* yyjson points at the character after the backslash; the reference decoder at the backslash. */
      return fail_with(L, "invalid_escape", (lua_Integer)(pos > 0 && text[pos - 1] == '\\' ? pos - 1 : pos),
                       "invalid escape in string");
    default: /* unexpected character or content, structure, literal */
      /* A trailing comma: yyjson points at the comma, the reference decoder at the closing bracket after it. */
      if (err->code == YYJSON_READ_ERROR_JSON_STRUCTURE && pos < length && text[pos] == ',') {
        size_t next = pos + 1;
        while (next < length && (text[next] == ' ' || text[next] == '\t' || text[next] == '\n' || text[next] == '\r')) next++;
        if (next < length && (text[next] == ']' || text[next] == '}')) pos = next;
      }
      if (err->code == YYJSON_READ_ERROR_JSON_STRUCTURE && pos > 0 && pos <= length &&
          (text[pos - 1] == ']' || text[pos - 1] == '}') && !(pos < length && (text[pos] == ']' || text[pos] == '}'))) {
        /* The same trailing comma, reported after the closing bracket. */
        size_t before = pos - 1;
        while (before > 0 && (text[before - 1] == ' ' || text[before - 1] == '\t' || text[before - 1] == '\n' ||
                              text[before - 1] == '\r'))
          before--;
        if (before > 0 && text[before - 1] == ',') pos = pos - 1;
      }
      /* A bad literal (`tru`, `nul`): yyjson points past what it read, the reference decoder at its first letter. */
      if (err->code == YYJSON_READ_ERROR_LITERAL) {
        if (pos > length) pos = length;
        while (pos > 0 && text[pos - 1] >= 'a' && text[pos - 1] <= 'z') pos--;
      }
      push_describe(L, text, length, pos);
      lua_pushfstring(L, "unexpected %s", lua_tostring(L, -1));
      lua_remove(L, -2);
      return push_failure(L, "syntax", (lua_Integer)pos);
  }
}

/* decode(text, options) -> value | nil, failure   (options: { max_depth, max_size }, validated).
 * Every failure is produced here, from the error of yyjson, with no second parse. The reference decoder answers
 * only for "-0" (an integer literal that yyjson reads as a negative zero float) and, as a safety net, for a nesting
 * beyond the ceiling of the converter. */
static int native_decode(lua_State *L) {
  hecate_json_state *state = get_state(L);
  size_t length;
  const char *text = luaL_checklstring(L, 1, &length);
  luaL_checktype(L, 2, LUA_TTABLE);
  lua_getfield(L, 2, "max_depth");
  lua_getfield(L, 2, "max_size");
  lua_Integer max_depth = luaL_checkinteger(L, -2);
  lua_Integer max_size = luaL_checkinteger(L, -1);
  lua_pop(L, 2);

  if ((lua_Integer)length > max_size) {
    lua_pushfstring(L, "input of %I bytes exceeds max_size (%I)", (lua_Integer)length, max_size);
    return push_failure(L, "size_limit", 0);
  }
  if (length >= 3 && memcmp(text, "\xEF\xBB\xBF", 3) == 0)
    return fail_with(L, "byte_order_mark", 0,
                     "the text starts with a byte order mark: RFC 8259 section 8.1 lets a parser ignore it but parsers "
                     "disagree, so it is rejected; strip the first three bytes (EF BB BF) before decoding");
  if (length == 0) return fail_with(L, "syntax", 0, "unexpected end of input");
  lua_Integer too_deep = first_too_deep(text, length, max_depth);
  if (too_deep >= 0) {
    lua_pushfstring(L, "nesting deeper than max_depth (%I)", max_depth);
    return push_failure(L, "depth_limit", too_deep);
  }

  yyjson_read_err err;
  yyjson_doc *doc = yyjson_read_opts((char *)text, length, YYJSON_READ_NOFLAG, NULL, &err);
  if (doc == NULL) return classify(L, text, length, &err);

  conversion c = { state, yyjson_doc_get_root(doc), max_depth, NULL };
  int top = lua_gettop(L);
  lua_pushcfunction(L, convert_protected);
  lua_pushlightuserdata(L, &c);
  int status = lua_pcall(L, 1, 1, 0);
  if (status != LUA_OK) {
    yyjson_doc_free(doc); /* freed on a Lua error (out of memory, stack overflow) as on success */
    return lua_error(L);
  }
  if (!lua_isnil(L, -1)) {
    yyjson_doc_free(doc);
    return 1;
  }
  lua_settop(L, top);
  if (c.duplicate != NULL) {
    lua_pushstring(L, "duplicate member name ");
    push_excerpt(L, yyjson_get_str(c.duplicate), yyjson_get_len(c.duplicate));
    lua_pushstring(L, ": RFC 8259 allows it but parsers disagree on which value wins, so it is rejected (I-JSON, RFC 7493 "
                      "section 2.3)");
    lua_concat(L, 3);
    yyjson_doc_free(doc);
    return push_failure(L, "duplicate_key", -1);
  }
  yyjson_doc_free(doc);
  return delegate(L, state->decode_ref, 2);
}

static const luaL_Reg state_methods[] = { { "__gc", state_gc }, { NULL, NULL } };

/* Requires a module and leaves it on the stack. */
static void require_module(lua_State *L, const char *module) {
  lua_getglobal(L, "require");
  lua_pushstring(L, module);
  lua_call(L, 1, 1);
}

/* Keeps field `field` of the module on top of the stack in *ref (the module stays). */
static void keep_field(lua_State *L, const char *field, int *ref) {
  lua_getfield(L, -1, field);
  keep(L, ref);
}

int luaopen_hecate_json_native(lua_State *L) {
  hecate_json_state *state = (hecate_json_state *)lua_newuserdatauv(L, sizeof(hecate_json_state), 0);
  state->null_ref = state->array_ref = state->object_ref = LUA_NOREF;
  state->decode_ref = state->encode_ref = LUA_NOREF;
  if (luaL_newmetatable(L, STATE_METATABLE)) luaL_setfuncs(L, state_methods, 0);
  lua_setmetatable(L, -2); /* from here on, an error frees what was kept */
  const int state_index = lua_gettop(L); /* below it: the arguments of luaopen */

  /* Delegation targets: the reference backend (the failure path of decode, and encode). */
  require_module(L, REFERENCE_MODULE);
  keep_field(L, "decode", &state->decode_ref);
  keep_field(L, "encode", &state->encode_ref);
  lua_pop(L, 1);

  /* The module table; every function shares the state as its upvalue. */
  lua_newtable(L); /* stack: state, module */
  lua_pushvalue(L, state_index);
  lua_pushcclosure(L, native_bind, 1);
  lua_setfield(L, -2, "bind");
  lua_pushvalue(L, state_index);
  lua_pushcclosure(L, native_decode, 1);
  lua_setfield(L, -2, "decode");
  lua_pushvalue(L, state_index);
  lua_pushcclosure(L, native_encode, 1);
  lua_setfield(L, -2, "encode");

  /* Bound at once to the markers of the Lua side, so that decode works before bind is called. */
  require_module(L, MARKERS_MODULE);
  lua_getfield(L, -2, "bind");
  lua_pushvalue(L, -2);
  lua_call(L, 1, 0);
  lua_pop(L, 1);
  return 1;
}
