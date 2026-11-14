#include <lua.h>
#include <lauxlib.h>
int luaopen_hecate_json_native(lua_State *L); int luaopen_hecate_json_encoder_native(lua_State *L);
void preload_natives(lua_State *L) {
  luaL_getsubtable(L, LUA_REGISTRYINDEX, LUA_PRELOAD_TABLE);
  lua_pushcfunction(L, luaopen_hecate_json_native);
  lua_setfield(L, -2, "hecate.json.native");
  lua_pushcfunction(L, luaopen_hecate_json_encoder_native);
  lua_setfield(L, -2, "hecate.json.encoder_native");
  lua_pop(L, 1);
}
