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

# Pinned versions and SHA-256 checksums live in tools/bootstrap/bootstrap.sh. This
# script is pasted into the environment, so it fetches the bootstrap from the repository.
curl -fsSL https://raw.githubusercontent.com/hecate-framework/hecate/main/tools/bootstrap/bootstrap.sh \
  -o /tmp/hecate-bootstrap.sh
bash /tmp/hecate-bootstrap.sh --prefix /opt/lua-5.5 --link /usr/local/bin

# Optional: luv (libuv binding). Its Lua 5.5 support is what spike OQ-1 verifies, so a
# failure here must not block the session.
luarocks install luv >/dev/null 2>&1 || echo "luv not installed (see OQ-1)"

exit 0
