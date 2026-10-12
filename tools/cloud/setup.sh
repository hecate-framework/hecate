#!/bin/bash
# Setup script for the Hecate cloud environment (Claude Code cloud sessions).
# Paste this file's content into the environment's "Setup script" field at
# claude.ai/code. It runs as root on Ubuntu 24.04 before Claude Code starts, and must
# finish in about five minutes so the environment can be cached.
#
# Delegates to tools/bootstrap/bootstrap.sh (pinned versions, SHA-256 checksums).
set -euo pipefail

apt-get update -qq
apt-get install -y -qq libreadline-dev libssl-dev unzip >/dev/null || true

# This script is pasted into the environment, so it cannot know its own commit. It pins
# the bootstrap it was written for by commit and SHA-256: the same bootstrap behaviour
# every time, whatever happens on main. When tools/bootstrap/ changes, update both
# values below (and re-paste this script into the environment).
BOOTSTRAP_REF=6f70123dfc30a27930253656ec30a47f52714f7a
BOOTSTRAP_SHA256=39e10e2877ccd36354e8c75e0d0454fa6a3dc96edf69736b240402bdee68c307
curl -fsSL "https://raw.githubusercontent.com/hecate-framework/hecate/${BOOTSTRAP_REF}/tools/bootstrap/bootstrap.sh" \
  -o /tmp/hecate-bootstrap.sh
echo "${BOOTSTRAP_SHA256}  /tmp/hecate-bootstrap.sh" | sha256sum -c -
bash /tmp/hecate-bootstrap.sh --prefix /opt/lua-5.5 --link /usr/local/bin

# Optional: luv (libuv binding). Its Lua 5.5 support is what spike OQ-1 verifies, so a
# failure here must not block the session.
luarocks install luv >/dev/null 2>&1 || echo "luv not installed (see OQ-1)"

exit 0
