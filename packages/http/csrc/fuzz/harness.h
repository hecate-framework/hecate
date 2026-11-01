/*
 * Shared setup of the libFuzzer target of hecate.http.native: one Lua state for the whole run and the native module
 * loaded into it. The harness includes native.c itself (no shared object, no `require`) and the target links the llhttp
 * sources, so that the sanitizers instrument the binding as well as llhttp.
 */
#ifndef HECATE_HTTP_FUZZ_HARNESS_H
#define HECATE_HTTP_FUZZ_HARNESS_H

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

#include "lualib.h"

/* The llhttp sources are linked as separate translation units (extra_sources.txt): the generated parser and its API
 * declare the same callbacks with different pointer types, which only separate units tolerate. */
#include "../native.c"

/* Feeds `data` to a parser in pieces whose sizes come from `plan`: a parser must give the same verdict however the
 * bytes are split, and never raise. Small limits make the limit paths reachable from short inputs. */
static const char *const DRIVER =
    "local native = ...\n"
    "return function(kind, data, plan)\n"
    "  local p = native.new(kind, { max_target_size = 64, max_field_size = 48, max_head_size = 300,\n"
    "    max_fields = 8, max_events = 3 })\n"
    "  local i, k = 0, 1\n"
    "  while i < #data do\n"
    "    local n = (plan:byte(k) or 255) % 40 + 1\n"
    "    k = k % math.max(#plan, 1) + 1\n"
    "    local start = 0\n"
    "    local piece = data:sub(i + 1, i + n)\n"
    "    repeat\n"
    "      local _, failure, consumed = p:execute(piece, start)\n"
    "      if failure then goto done end\n"
    "      if consumed <= start then break end\n"
    "      start = consumed\n"
    "    until start >= #piece\n"
    "    i = i + n\n"
    "  end\n"
    "  p:finish()\n"
    "  ::done::\n"
    "  p:close()\n"
    "end\n";

static lua_State *fuzz_state(void) {
  static lua_State *L = NULL;
  if (L != NULL) return L;
  L = luaL_newstate();
  if (L == NULL) abort();
  luaL_openlibs(L);
  luaopen_hecate_http_native(L);
  if (luaL_loadstring(L, DRIVER) != LUA_OK) abort();
  lua_insert(L, -2);
  if (lua_pcall(L, 1, 1, 0) != LUA_OK) abort();
  lua_setglobal(L, "drive");
  return L;
}

#endif
