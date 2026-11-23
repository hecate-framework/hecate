/*
 * The `hecate` executable: Lua 5.5 with the command-line interface embedded (ADR 0029).
 *
 *   hecate <command> ...      runs hecate.cli.main
 *   hecate --lua [options]    acts as a Lua interpreter ("-v", "-e chunk", "--", "<script> <args>")
 *   hecate -e <chunk> ...     the same, as a plain `lua -e` (LuaRocks runs its LUA variable like that)
 *   hecate --luarocks ...     the embedded LuaRocks, as the `luarocks` program
 *
 * The Lua sources of the embedded packages are compiled into the program (bundle.c); a searcher placed
 * before the file searcher serves them. Native modules (luv, the JSON codec, ...) are found through
 * LUA_CPATH and the directory next to the executable.
 */
#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#define _DARWIN_C_SOURCE
#endif

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#include <limits.h>
#include <unistd.h>
#endif

#include "lauxlib.h"
#include "lua.h"
#include "lualib.h"

#include "bundle.h"

#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif

/* ---- statically linked native modules (the build defines the HECATE_STATIC_* macros of those it linked) ---- */

#ifdef HECATE_STATIC_LUV
int luaopen_luv(lua_State *L);
#endif
#ifdef HECATE_STATIC_LFS
int luaopen_lfs(lua_State *L);
#endif
#ifdef HECATE_STATIC_DIGEST
int luaopen_digest(lua_State *L);
#endif
#ifdef HECATE_STATIC_JSON_DECODER
int luaopen_hecate_json_native(lua_State *L);
#endif
#ifdef HECATE_STATIC_JSON_ENCODER
int luaopen_hecate_json_encoder_native(lua_State *L);
#endif

static void preload_natives(lua_State *L) {
  static const luaL_Reg natives[] = {
#ifdef HECATE_STATIC_LUV
    { "luv", luaopen_luv },
#endif
#ifdef HECATE_STATIC_LFS
    { "lfs", luaopen_lfs },
#endif
#ifdef HECATE_STATIC_DIGEST
    { "digest", luaopen_digest },
#endif
#ifdef HECATE_STATIC_JSON_DECODER
    { "hecate.json.native", luaopen_hecate_json_native },
#endif
#ifdef HECATE_STATIC_JSON_ENCODER
    { "hecate.json.encoder_native", luaopen_hecate_json_encoder_native },
#endif
    { NULL, NULL }
  };
  luaL_getsubtable(L, LUA_REGISTRYINDEX, LUA_PRELOAD_TABLE);
  for (const luaL_Reg *r = natives; r->name; r++) {
    lua_pushcfunction(L, r->func);
    lua_setfield(L, -2, r->name);
  }
  lua_pop(L, 1);
}

/* ---- embedded modules -------------------------------------------------- */

static int embedded_searcher(lua_State *L) {
  const char *name = luaL_checkstring(L, 1);
  for (const hecate_module *m = hecate_modules; m->name; m++) {
    if (strcmp(m->name, name) == 0) {
      char chunk[256];
      snprintf(chunk, sizeof chunk, "=%s", name);
      if (luaL_loadbuffer(L, m->source, m->length, chunk) != LUA_OK) {
        return luaL_error(L, "error loading embedded module '%s':\n\t%s", name, lua_tostring(L, -1));
      }
      lua_pushliteral(L, ":embedded");
      return 2;
    }
  }
  lua_pushfstring(L, "no embedded module '%s'", name);
  return 1;
}

static void install_searcher(lua_State *L) {
  lua_getglobal(L, "package");
  lua_getfield(L, -1, "searchers");
  lua_Integer n = (lua_Integer)luaL_len(L, -1);
  for (lua_Integer i = n; i >= 2; i--) { /* make room at position 2, after the preload searcher */
    lua_geti(L, -1, i);
    lua_seti(L, -2, i + 1);
  }
  lua_pushcfunction(L, embedded_searcher);
  lua_seti(L, -2, 2);
  lua_pop(L, 2);
}

/* ---- executable path and native module directory ----------------------- */

static int executable_path(char *buffer, size_t size, const char *argv0) {
#if defined(_WIN32)
  DWORD n = GetModuleFileNameA(NULL, buffer, (DWORD)size);
  if (n > 0 && n < size) return 1;
  (void)argv0;
  return 0;
#elif defined(__linux__)
  ssize_t n = readlink("/proc/self/exe", buffer, size - 1);
  if (n > 0) { buffer[n] = '\0'; return 1; }
#elif defined(__APPLE__)
  uint32_t length = (uint32_t)size;
  if (_NSGetExecutablePath(buffer, &length) == 0) return 1;
#endif
#if !defined(_WIN32)
  if (argv0 && realpath(argv0, buffer)) return 1;
  return 0;
#endif
}

static void add_native_directory(lua_State *L, const char *path) {
  const char *slash = strrchr(path, '/');
#ifdef _WIN32
  const char *backslash = strrchr(path, '\\');
  if (backslash && (!slash || backslash > slash)) slash = backslash;
#endif
  if (!slash) return;
  char directory[4096];
  size_t length = (size_t)(slash - path);
  if (length >= sizeof directory) return;
  memcpy(directory, path, length);
  directory[length] = '\0';
  lua_getglobal(L, "package");
  lua_getfield(L, -1, "cpath");
#ifdef _WIN32
  lua_pushfstring(L, "%s;%s\\?.dll;%s\\lib\\?.dll", lua_tostring(L, -1), directory, directory);
#else
  lua_pushfstring(L, "%s;%s/?.so;%s/lib/?.so", lua_tostring(L, -1), directory, directory);
#endif
  lua_setfield(L, -3, "cpath");
  lua_pop(L, 2);
}

/* ---- running ----------------------------------------------------------- */

static int traceback(lua_State *L) {
  const char *message = lua_tostring(L, 1);
  if (message == NULL) {
    if (luaL_callmeta(L, 1, "__tostring") && lua_type(L, -1) == LUA_TSTRING) return 1;
    message = lua_pushfstring(L, "(error object is a %s value)", luaL_typename(L, 1));
  }
  luaL_traceback(L, L, message, 1);
  return 1;
}

static int docall(lua_State *L, int narguments, int nresults) {
  int base = lua_gettop(L) - narguments;
  lua_pushcfunction(L, traceback);
  lua_insert(L, base);
  int status = lua_pcall(L, narguments, nresults, base);
  lua_remove(L, base);
  return status;
}

static const char *program_name = "hecate"; /* prefix of the errors: "lua" in interpreter mode, "luarocks" for LuaRocks */

static int report(lua_State *L, int status) {
  if (status != LUA_OK) {
    const char *message = lua_tostring(L, -1);
    fprintf(stderr, "%s: %s\n", program_name, message ? message : "(error object is not a string)");
    lua_pop(L, 1);
    return 1;
  }
  return 0;
}

/* Sets the global `arg`: arg[0] is the script, negative indexes the interpreter and its options. */
static void create_arg_table(lua_State *L, char **argv, int argc, int script) {
  lua_createtable(L, argc - script - 1 > 0 ? argc - script - 1 : 0, script + 1);
  for (int i = 0; i < argc; i++) {
    lua_pushstring(L, argv[i]);
    lua_rawseti(L, -2, i - script);
  }
  lua_setglobal(L, "arg");
}

static int run_interpreter(lua_State *L, int argc, char **argv, int first) {
  int i = first; /* 2 after --lua; 1 when invoked as a plain `lua -e ...` */
  int script = 0;
  int ran = 0;
  for (; i < argc; i++) {
    const char *a = argv[i];
    if (strcmp(a, "--") == 0) { i++; break; }
    if (strcmp(a, "-v") == 0) {
      printf("%s\n", LUA_COPYRIGHT);
      ran = 1;
    } else if (strcmp(a, "-e") == 0) {
      if (i + 1 >= argc) { fprintf(stderr, "lua: '-e' needs an argument\n"); return 1; }
      i++;
      create_arg_table(L, argv, argc, 0);
      if (report(L, luaL_loadbuffer(L, argv[i], strlen(argv[i]), "=(command line)")) ||
          report(L, docall(L, 0, 0))) return 1;
      ran = 1;
    } else if (a[0] == '-' && a[1] != '\0') {
      fprintf(stderr, "lua: unrecognized option '%s'\n", a);
      return 1;
    } else {
      break;
    }
  }
  if (i < argc) {
    script = i;
    create_arg_table(L, argv, argc, script);
    if (report(L, luaL_loadfile(L, argv[script]))) return 1;
    int narguments = 0;
    luaL_checkstack(L, argc - script + 4, "too many arguments");
    for (int j = script + 1; j < argc; j++) { lua_pushstring(L, argv[j]); narguments++; }
    return report(L, docall(L, narguments, 0));
  }
  if (!ran) { fprintf(stderr, "usage: hecate --lua [-v] [-e chunk] [--] [script [args]]\n"); return 1; }
  return 0;
}

/* `hecate --luarocks <arguments>`: the embedded LuaRocks, as the `luarocks` program. */
static int run_luarocks(lua_State *L, int argc, char **argv) {
#ifdef HECATE_EMBEDDED_LUAROCKS
  create_arg_table(L, argv, argc, 1); /* arg[0] is "--luarocks" */
  lua_getglobal(L, "arg");
  lua_pushliteral(L, "luarocks"); /* the program name, in place of "--luarocks" */
  lua_rawseti(L, -2, 0);
  lua_pop(L, 1);
  for (const hecate_module *m = hecate_modules; m->name; m++) {
    if (strcmp(m->name, "luarocks.main") == 0) {
      if (report(L, luaL_loadbuffer(L, m->source, m->length, "=luarocks"))) return 1;
      luaL_checkstack(L, argc + 4, "too many arguments");
      for (int i = 2; i < argc; i++) lua_pushstring(L, argv[i]);
      return report(L, docall(L, argc - 2, 0));
    }
  }
#else
  (void)argc; (void)argv;
#endif
  fprintf(stderr, "hecate: this executable was built without LuaRocks\n");
  (void)L;
  return 1;
}

static int run_cli(lua_State *L, int argc, char **argv, const char *self) {
  create_arg_table(L, argv, argc, 0);
  lua_getglobal(L, "require");
  lua_pushliteral(L, "hecate.cli.main");
  if (report(L, docall(L, 1, 1))) return 1;
  lua_getfield(L, -1, "run");
  lua_getglobal(L, "arg");
  lua_createtable(L, 0, 4); /* overrides: the executable is the project interpreter (--lua) and runs LuaRocks (--luarocks) */
  lua_pushstring(L, self);
  lua_setfield(L, -2, "luarocks_program");
  lua_createtable(L, 1, 0);
  lua_pushliteral(L, "--luarocks");
  lua_rawseti(L, -2, 1);
  lua_setfield(L, -2, "luarocks_arguments");
  lua_pushstring(L, self);
  lua_setfield(L, -2, "lua_interpreter");
  lua_createtable(L, 1, 0);
  lua_pushliteral(L, "--lua");
  lua_rawseti(L, -2, 1);
  lua_setfield(L, -2, "lua_interpreter_arguments");
  if (report(L, docall(L, 2, 1))) return 1;
  int code = 1; /* a result that is not an integer is a failure, never a silent success */
  if (lua_isinteger(L, -1)) {
    lua_Integer value = lua_tointeger(L, -1);
    code = (value < 0 || value > 255) ? 1 : (int)value;
  } else if (lua_isboolean(L, -1)) {
    code = lua_toboolean(L, -1) ? 0 : 1;
  }
  lua_pop(L, 2);
  return code;
}

int main(int argc, char **argv) {
  lua_State *L = luaL_newstate();
  if (!L) { fprintf(stderr, "hecate: cannot create the Lua state\n"); return 1; }
  luaL_openlibs(L);
  preload_natives(L);
  install_searcher(L);
  char self[4096];
  if (!executable_path(self, sizeof self, argc > 0 ? argv[0] : NULL)) snprintf(self, sizeof self, "%s", argc > 0 ? argv[0] : "hecate");
  add_native_directory(L, self);
  int code;
  size_t first_length = argc > 1 ? strlen(argv[1]) : 0;
  if (argc > 1 && strcmp(argv[1], "--lua") == 0) { program_name = "lua"; code = run_interpreter(L, argc, argv, 2); }
  else if (argc > 1 && first_length > 4 && strcmp(argv[1] + first_length - 4, ".lua") == 0) { /* `$(LUA) script.lua` of a rockspec */
    program_name = "lua";
    code = run_interpreter(L, argc, argv, 1);
  }
  else if (argc > 2 && strcmp(argv[1], "-e") == 0) { program_name = "lua"; code = run_interpreter(L, argc, argv, 1); } /* LuaRocks probes its `LUA` this way */
  else if (argc > 1 && strcmp(argv[1], "--luarocks") == 0) { program_name = "luarocks"; code = run_luarocks(L, argc, argv); }
  else code = run_cli(L, argc, argv, self);
  lua_close(L);
  return code;
}
