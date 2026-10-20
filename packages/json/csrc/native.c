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
} conversion;

static void mark(lua_State *L, int ref) {
  lua_rawgeti(L, LUA_REGISTRYINDEX, ref);
  lua_setmetatable(L, -2);
}

/*
 * Pushes the Lua value of `val`. Returns 0 when the text must be classified by the reference backend
 * (a duplicate member name, a nesting beyond max_depth, a float outside the 64-bit range, "-0"), in which
 * case nothing is left on the stack. `depth` is the nesting level of the containers around `val`.
 */
static int convert(lua_State *L, const conversion *c, yyjson_val *val, lua_Integer depth) {
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
        /* RFC 7493 section 2.3: a duplicate member name is rejected (by the reference classification). */
        if (!lua_isnil(L, -1)) return 0;
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

/* decode(text, options) -> value | nil, failure   (options: { max_depth, max_size }, validated) */
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

  yyjson_doc *doc = NULL;
  /* A text beyond max_size, and a byte order mark (RFC 8259 section 8.1), are classified by the reference. */
  int plausible = (lua_Integer)length <= max_size && length > 0 &&
                  !(length >= 3 && memcmp(text, "\xEF\xBB\xBF", 3) == 0);
  if (plausible) doc = yyjson_read_opts((char *)text, length, YYJSON_READ_NOFLAG, NULL, NULL);
  if (doc != NULL) {
    conversion c = { state, yyjson_doc_get_root(doc), max_depth };
    int top = lua_gettop(L);
    lua_pushcfunction(L, convert_protected);
    lua_pushlightuserdata(L, &c);
    int status = lua_pcall(L, 1, 1, 0);
    yyjson_doc_free(doc); /* freed on success and on a Lua error (out of memory, stack overflow) alike */
    if (status != LUA_OK) return lua_error(L);
    if (!lua_isnil(L, -1)) return 1;
    lua_settop(L, top);
  }
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
