#!/bin/bash
# Pinned bootstrap: builds Lua and LuaRocks from source with verified SHA-256 checksums.
#
# Usage: tools/bootstrap/bootstrap.sh [--prefix DIR] [--link DIR]
#   --prefix DIR  install location (default: /opt/lua-5.5)
#   --link DIR    also symlink the installed binaries into DIR (e.g. /usr/local/bin)
#
# Used by the cloud environment setup script (tools/cloud/setup.sh). The contributor
# variant installing into .hecate/toolchain/ reuses it with --prefix.
set -euo pipefail

LUA_VERSION=5.5.1
LUA_SHA256=1c4b4068d67061f2a2231ad2b5422e77acea1487ea9890f6320af614f4373dce
LUAROCKS_VERSION=3.13.0
LUAROCKS_SHA256=245bf6ec560c042cb8948e3d661189292587c5949104677f1eecddc54dbe7e37

PREFIX=/opt/lua-5.5
LINK=""
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2 ;;
    --link) LINK="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

# Relative prefixes are resolved against the caller's directory: the build runs elsewhere.
mkdir -p "$PREFIX"
PREFIX="$(cd "$PREFIX" && pwd)"

case "$(uname -s)" in
  Linux) PLATFORM=linux ;;
  Darwin) PLATFORM=macosx ;;
  *) echo "unsupported platform: $(uname -s)" >&2; exit 1 ;;
esac

if command -v sha256sum >/dev/null 2>&1; then
  sha256() { sha256sum "$1" | cut -d' ' -f1; }
else
  sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fetch() { # url sha256 file
  curl -fsSL "$1" -o "$WORK/$3"
  if [ "$(sha256 "$WORK/$3")" != "$2" ]; then
    echo "checksum mismatch for $3" >&2
    exit 1
  fi
}

fetch "https://www.lua.org/ftp/lua-${LUA_VERSION}.tar.gz" "$LUA_SHA256" lua.tar.gz
fetch "https://luarocks.org/releases/luarocks-${LUAROCKS_VERSION}.tar.gz" "$LUAROCKS_SHA256" luarocks.tar.gz

tar -xzf "$WORK/lua.tar.gz" -C "$WORK"
make -C "$WORK/lua-${LUA_VERSION}" -j4 "$PLATFORM" >/dev/null
make -C "$WORK/lua-${LUA_VERSION}" install INSTALL_TOP="$PREFIX" >/dev/null

tar -xzf "$WORK/luarocks.tar.gz" -C "$WORK"
(cd "$WORK/luarocks-${LUAROCKS_VERSION}" \
  && ./configure --prefix="$PREFIX" --with-lua="$PREFIX" >/dev/null \
  && make >/dev/null && make install >/dev/null)

if [ -n "$LINK" ]; then
  ln -sf "$PREFIX"/bin/* "$LINK"/
fi

"$PREFIX/bin/lua" -v
"$PREFIX/bin/luarocks" --version | head -1
