-- The `hecate` command. Usage: lua packages/cli/bin/hecate.lua <command> [options]
-- This is the entry point of a monorepo checkout and of an installed rock; the self-contained executable
-- (OQ-13, ADR 0029) runs the same `hecate.cli.main`.
-- Exit codes: 0 ok, 1 the command failed, 2 usage error.
global <const> arg, os, package, require, ipairs, _VERSION

local script = arg[0]:gsub("\\", "/")
local here = script:match("^(.*)/[^/]*$") or "."
-- Monorepo checkout: the sources of this package and of its dependencies. An installed rock has them on the path.
for _, package_name in ipairs({ "cli", "core", "json", "log", "openapi", "reactor", "router", "schema" }) do
  local base = here .. "/../../" .. package_name .. "/src/"
  package.path = base .. "?.lua;" .. base .. "?/init.lua;" .. package.path
end

-- Project-local LuaRocks tree of a monorepo checkout (`.hecate/rocks`: luv for the reactor, the SHA-256 rocks), as in
-- tools/harness/run_file.lua. An installed rock has them on the path already.
do
  local version = _VERSION:match("%d+%.%d+")
  local tree = here .. "/../../../.hecate/rocks"
  package.path = tree .. "/share/lua/" .. version .. "/?.lua;" .. tree .. "/share/lua/" .. version
    .. "/?/init.lua;" .. package.path
  package.cpath = tree .. "/lib/lua/" .. version .. "/?.so;" .. tree .. "/lib/lua/" .. version
    .. "/?.dll;" .. package.cpath
end

os.exit(require("hecate.cli.main").run(arg))
