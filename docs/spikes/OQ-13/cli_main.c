#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <stdio.h>
extern const unsigned char cli_bc[]; extern const unsigned long cli_len;
int main(int argc, char **argv) {
  lua_State *L = luaL_newstate(); luaL_openlibs(L);
  lua_createtable(L, argc, 0);
  for (int i = 0; i < argc; i++) { lua_pushstring(L, argv[i]); lua_rawseti(L, -2, i); }
  lua_setglobal(L, "arg");
  if (luaL_loadbufferx(L, (const char *)cli_bc, cli_len, "cli", "b") || lua_pcall(L, 0, 0, 0)) { fprintf(stderr, "%s\n", lua_tostring(L, -1)); return 1; }
  return 0;
}
