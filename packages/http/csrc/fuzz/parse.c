/*
 * libFuzzer target `parse`: arbitrary bytes to the request parser and to the response parser of hecate.http.native,
 * split into pieces of random sizes (the first bytes of the input are the split plan), with small limits. A Lua
 * error, a crash or a sanitizer report is a finding.
 */
#include "harness.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  lua_State *L = fuzz_state();
  size_t plan = size < 8 ? size : 8;
  for (int kind = 0; kind < 2; kind++) {
    lua_getglobal(L, "drive");
    lua_pushstring(L, kind == 0 ? "request" : "response");
    lua_pushlstring(L, (const char *)data + plan, size - plan);
    lua_pushlstring(L, (const char *)data, plan);
    if (lua_pcall(L, 3, 0, 0) != LUA_OK) abort();
  }
  return 0;
}
