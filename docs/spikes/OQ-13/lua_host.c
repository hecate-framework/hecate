#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <stdio.h>
int main(int argc, char **argv) {
  lua_State *L = luaL_newstate(); luaL_openlibs(L);
  lua_createtable(L, argc, 0);
  for (int i = 0; i < argc; i++) { lua_pushstring(L, argv[i]); lua_rawseti(L, -2, i - 1); }
  lua_setglobal(L, "arg");
  if (luaL_loadfile(L, argv[1])) { fprintf(stderr, "%s\n", lua_tostring(L, -1)); return 1; }
  for (int i = 2; i < argc; i++) { lua_pushstring(L, argv[i]); }
  if (lua_pcall(L, argc - 2, LUA_MULTRET, 0)) { fprintf(stderr, "%s\n", lua_tostring(L, -1)); return 1; }
  return 0;
}
