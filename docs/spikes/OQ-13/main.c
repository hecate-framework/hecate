#include <stdio.h>
#include <string.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
struct embedded { const char *name; const unsigned char *data; size_t len; };
extern const struct embedded embedded_modules[];
int luaopen_luv(lua_State *L); void preload_natives(lua_State *L);
static int searcher(lua_State *L) {
  const char *name = luaL_checkstring(L, 1);
  for (const struct embedded *e = embedded_modules; e->name; e++)
    if (strcmp(e->name, name) == 0) {
      if (luaL_loadbufferx(L, (const char *)e->data, e->len, name, "b") != 0) return lua_error(L);
      lua_pushstring(L, ":embedded");
      return 2;
    }
  lua_pushfstring(L, "no embedded module '%s'", name);
  return 1;
}
int main(int argc, char **argv) {
  lua_State *L = luaL_newstate();
  luaL_openlibs(L);
  luaL_requiref(L, "luv", luaopen_luv, 0); lua_pop(L, 1); preload_natives(L);
  lua_getglobal(L, "package"); lua_getfield(L, -1, "searchers");
  lua_pushcfunction(L, searcher);
  lua_rawseti(L, -2, luaL_len(L, -2) + 1);
  lua_pop(L, 2);
  lua_createtable(L, argc, 0);
  for (int i = 0; i < argc; i++) { lua_pushstring(L, argv[i]); lua_rawseti(L, -2, i); }
  lua_setglobal(L, "arg");
  int rc = argc > 1 ? luaL_dofile(L, argv[1]) : luaL_dostring(L, "print(_VERSION)");
  if (rc) { fprintf(stderr, "%s\n", luaL_tolstring(L, -1, NULL)); return 1; }
  lua_close(L); return 0;
}
