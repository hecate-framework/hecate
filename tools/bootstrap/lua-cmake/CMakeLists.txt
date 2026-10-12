# Minimal CMake build of the official Lua tarball, used by bootstrap.ps1 on Windows
# (the tarball ships a Makefile only). Usage:
#   cmake -S tools/bootstrap/lua-cmake -B build -DLUA_SRC=<path to lua-5.5.x/src> -DLUA_ABI=55
#   cmake --build build --config Release && cmake --install build --config Release --prefix <dir>
# Produces lua.exe, luac.exe, lua<ABI>.dll and its import library lua<ABI>.lib, plus headers.
cmake_minimum_required(VERSION 3.15)
project(lua C)

set(LUA_SRC "" CACHE PATH "Lua src directory")
set(LUA_ABI "55" CACHE STRING "Library suffix, e.g. 55 for lua55.dll")
if(NOT LUA_SRC)
  message(FATAL_ERROR "LUA_SRC is required")
endif()

file(GLOB LUA_CORE "${LUA_SRC}/*.c")
list(FILTER LUA_CORE EXCLUDE REGEX "/(lua|luac)\\.c$")

add_library(lualib SHARED ${LUA_CORE})
set_target_properties(lualib PROPERTIES OUTPUT_NAME "lua${LUA_ABI}")
target_compile_definitions(lualib PRIVATE LUA_BUILD_AS_DLL)
target_compile_definitions(lualib PRIVATE _CRT_SECURE_NO_WARNINGS)

add_executable(lua "${LUA_SRC}/lua.c")
target_link_libraries(lua lualib)
target_compile_definitions(lua PRIVATE _CRT_SECURE_NO_WARNINGS)

# luac needs the core compiled in (it uses non-exported internals).
add_executable(luac "${LUA_SRC}/luac.c" ${LUA_CORE})
target_compile_definitions(luac PRIVATE _CRT_SECURE_NO_WARNINGS MAKE_LUAC)

install(TARGETS lua luac lualib RUNTIME DESTINATION bin ARCHIVE DESTINATION lib)
install(FILES "${LUA_SRC}/lua.h" "${LUA_SRC}/luaconf.h" "${LUA_SRC}/lualib.h"
              "${LUA_SRC}/lauxlib.h" "${LUA_SRC}/lua.hpp" DESTINATION include)
