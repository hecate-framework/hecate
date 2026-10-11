#!/bin/bash
# Setup script for the Hecate cloud environment (Claude Code cloud sessions).
# Paste this file's content into the environment's "Setup script" field at
# claude.ai/code. It runs as root on Ubuntu 24.04 before Claude Code starts, and must
# finish in about five minutes so the environment can be cached.
#
# Temporary: Phase 0 replaces this with tools/bootstrap/bootstrap.sh (pinned versions
# and SHA-256 checksums). Keep both in sync until then.
set -euo pipefail

LUA_VERSION=5.5.1          # check https://www.lua.org/ftp/ for the latest 5.5.x
LUAROCKS_VERSION=3.13.0    # first LuaRocks release supporting Lua 5.5
PREFIX=/opt/lua-5.5

apt-get update -qq
apt-get install -y -qq libreadline-dev libssl-dev unzip >/dev/null || true

cd /tmp
curl -fsSL "https://www.lua.org/ftp/lua-${LUA_VERSION}.tar.gz" | tar xz
make -C "lua-${LUA_VERSION}" -j4 linux >/dev/null
make -C "lua-${LUA_VERSION}" install INSTALL_TOP="${PREFIX}" >/dev/null

curl -fsSL "https://luarocks.org/releases/luarocks-${LUAROCKS_VERSION}.tar.gz" | tar xz
cd "luarocks-${LUAROCKS_VERSION}"
./configure --prefix="${PREFIX}" --with-lua="${PREFIX}" >/dev/null
make >/dev/null && make install >/dev/null
ln -sf "${PREFIX}"/bin/* /usr/local/bin/

# Optional: luv (libuv binding). Its Lua 5.5 support is what spike OQ-1 verifies, so a
# failure here must not block the session.
luarocks install luv >/dev/null 2>&1 || echo "luv not installed (see OQ-1)"

lua -v
luarocks --version | head -1
exit 0
