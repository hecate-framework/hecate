#!/usr/bin/env bash
# Verification of ADR 0029 on Linux and macOS: an executable that embeds Lua 5.5 and exports the Lua API
#   1. loads a native rock built by the standard toolchain (binary rock case);
#   2. runs LuaRocks itself (pure Lua) and installs a pure-Lua rock;
#   3. runs LuaRocks to build a source rock with a C module from the Lua headers, and loads it;
#   4. runs the contract test of the sha256 seam.
# usage: verify_interpreter.sh <toolchain prefix> <luarocks lib dir> <luarocks script> <work dir>
# env:   NATIVE_ROCK (default digest), PURE_ROCK (default plc)
set -euo pipefail
TC=$1; LRLIB=$2; LRBIN=$3; WORK=$4
NATIVE_ROCK=${NATIVE_ROCK:-digest}; PURE_ROCK=${PURE_ROCK:-plc}
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$WORK"
step() { printf '\n=== %s\n' "$*"; }

step "build the host (embedded Lua 5.5, Lua API exported to native modules)"
case "$(uname -s)" in
  Linux)  extra="-Wl,-E -ldl" ;;
  Darwin) extra="-Wl,-export_dynamic" ;;
  *) echo "unsupported system" >&2; exit 1 ;;
esac
cc -O2 -o "$WORK/host" "$HERE/lua_host.c" -I"$TC/include" "$TC/lib/liblua.a" -lm $extra
ls -l "$WORK/host"

step "1. the host loads a native rock built by the standard toolchain"
"$TC/bin/luarocks" --tree "$WORK/t1" install "$NATIVE_ROCK"
LUA_CPATH="$WORK/t1/lib/lua/5.5/?.so;;" "$WORK/host" "$HERE/check_native.lua" "$NATIVE_ROCK"

cat > "$WORK/lr-config.lua" <<CFG
variables = {
  LUA_DIR = "$TC", LUA_BINDIR = "$WORK", LUA_INCDIR = "$TC/include", LUA_LIBDIR = "$TC/lib",
  LUA_VERSION = "5.5", LUA = "$WORK/host",
}
CFG
export LUAROCKS_CONFIG="$WORK/lr-config.lua"
export LUA_PATH="$LRLIB/?.lua;;"

step "2. LuaRocks runs inside the host and installs a pure-Lua rock ($PURE_ROCK)"
"$WORK/host" "$LRBIN" --version
"$WORK/host" "$LRBIN" --tree "$WORK/t2" install "$PURE_ROCK"

step "3. LuaRocks runs inside the host and builds a source rock ($NATIVE_ROCK) from the Lua headers"
"$WORK/host" "$LRBIN" --tree "$WORK/t3" install "$NATIVE_ROCK"
LUA_PATH="$LRLIB/?.lua;;" LUA_CPATH="$WORK/t3/lib/lua/5.5/?.so;;" "$WORK/host" "$HERE/check_native.lua" "$NATIVE_ROCK"

step "4. the contract test of the sha256 seam runs in the host"
if [ "$NATIVE_ROCK" = digest ]; then
  LUA_PATH="$HERE/?.lua;$WORK/t2/share/lua/5.5/?.lua;;" LUA_CPATH="$WORK/t3/lib/lua/5.5/?.so;;" \
    "$WORK/host" "$HERE/digest_test.lua" digest
  LUA_PATH="$HERE/?.lua;$WORK/t2/share/lua/5.5/?.lua;;" LUA_CPATH="$WORK/t3/lib/lua/5.5/?.so;;" \
    "$WORK/host" "$HERE/digest_test.lua" plc
fi
printf '\nall checks passed\n'
