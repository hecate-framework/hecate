/* Throwaway OQ-5 binding: yyjson decode to Lua values. Integers stay integers, floats floats. */
#ifdef _WIN32
#define HECATE_EXPORT __declspec(dllexport)
#else
#define HECATE_EXPORT
#endif
#include <lua.h>
#include <lauxlib.h>
#include "yyjson.h"
static void push(lua_State *L, yyjson_val *v) {
  switch (yyjson_get_type(v)) {
  case YYJSON_TYPE_NULL: lua_pushlightuserdata(L, NULL); break;
  case YYJSON_TYPE_BOOL: lua_pushboolean(L, yyjson_get_bool(v)); break;
  case YYJSON_TYPE_NUM:
    switch (yyjson_get_subtype(v)) {
    case YYJSON_SUBTYPE_UINT: { uint64_t u = yyjson_get_uint(v);
      if (u <= (uint64_t)LUA_MAXINTEGER) lua_pushinteger(L, (lua_Integer)u); else lua_pushnumber(L, (lua_Number)u); break; }
    case YYJSON_SUBTYPE_SINT: lua_pushinteger(L, yyjson_get_sint(v)); break;
    default: lua_pushnumber(L, yyjson_get_real(v)); }
    break;
  case YYJSON_TYPE_STR: lua_pushlstring(L, yyjson_get_str(v), yyjson_get_len(v)); break;
  case YYJSON_TYPE_ARR: { size_t i, n; yyjson_val *e; lua_createtable(L, (int)yyjson_arr_size(v), 0);
    yyjson_arr_foreach(v, i, n, e) { push(L, e); lua_rawseti(L, -2, (lua_Integer)i + 1); } break; }
  case YYJSON_TYPE_OBJ: { size_t i, n; yyjson_val *k, *e; lua_createtable(L, 0, (int)yyjson_obj_size(v));
    yyjson_obj_foreach(v, i, n, k, e) { lua_pushlstring(L, yyjson_get_str(k), yyjson_get_len(k)); push(L, e); lua_rawset(L, -3); } break; }
  default: lua_pushnil(L);
  }
}
static int l_decode(lua_State *L) {
  size_t n; const char *s = luaL_checklstring(L, 1, &n);
  yyjson_read_err err; yyjson_doc *d = yyjson_read_opts((char *)s, n, 0, NULL, &err);
  if (!d) { lua_pushnil(L); lua_pushfstring(L, "%s at %d", err.msg, (int)err.pos); return 2; }
  luaL_checkstack(L, 200, "nesting"); push(L, yyjson_doc_get_root(d)); yyjson_doc_free(d); return 1;
}
HECATE_EXPORT int luaopen_yy(lua_State *L) { lua_pushcfunction(L, l_decode); return 1; }
