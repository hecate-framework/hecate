/*
 * Shared setup of the libFuzzer targets of hecate.json.native: one Lua state for the whole run, the native module
 * loaded into it, and `decode` called with the options a target chooses. The harness includes native.c itself
 * (no shared object, no `require` of the module) and yyjson.c so that the sanitizers instrument the binding as well as yyjson.
 */
#ifndef HECATE_JSON_FUZZ_HARNESS_H
#define HECATE_JSON_FUZZ_HARNESS_H

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

#include "lualib.h"

#include "../vendor/yyjson.c"
#include "../native.c"

/* A stand-in for hecate.json.internal.markers: the module only needs the `null` value and two metatables. */
static const char *const MARKERS_STUB =
    "package.loaded['hecate.json.internal.markers'] = {"
    " null = setmetatable({}, { __metatable = 'null' }),"
    " array_metatable = { __name = 'array' },"
    " object_metatable = { __name = 'object' } }";

static lua_State *fuzz_state(void) {
  static lua_State *L = NULL;
  if (L != NULL) return L;
  L = luaL_newstate();
  if (L == NULL) abort();
  luaL_openlibs(L);
  if (luaL_dostring(L, MARKERS_STUB) != LUA_OK) abort();
  luaopen_hecate_json_native(L);
  lua_setglobal(L, "native");
  return L;
}

/* Calls native.decode(text, { max_depth, max_size }) and discards the result. A Lua error is a finding. */
static void fuzz_decode(const uint8_t *data, size_t size, lua_Integer max_depth, lua_Integer max_size) {
  lua_State *L = fuzz_state();
  lua_getglobal(L, "native");
  lua_getfield(L, -1, "decode");
  lua_pushlstring(L, (const char *)data, size);
  lua_createtable(L, 0, 2);
  lua_pushinteger(L, max_depth);
  lua_setfield(L, -2, "max_depth");
  lua_pushinteger(L, max_size);
  lua_setfield(L, -2, "max_size");
  if (lua_pcall(L, 2, LUA_MULTRET, 0) != LUA_OK) abort();
  lua_settop(L, 0);
  lua_gc(L, LUA_GCCOLLECT);
}

#endif
