-- The `hecate` command. Usage: lua packages/cli/bin/hecate.lua <command> [options]
-- This is the entry point of a monorepo checkout and of an installed rock; the self-contained executable
-- (OQ-13, ADR 0029) embeds the same `hecate.cli.run`.
-- Exit codes: 0 ok, 1 the command failed, 2 usage error.
global <const> arg, io, os, package, require, pcall, ipairs, _VERSION

local script = arg[0]:gsub("\\", "/")
local here = script:match("^(.*)/[^/]*$") or "."
-- Monorepo checkout: the sources of this package and of its dependencies. An installed rock has them on the path.
for _, package_name in ipairs({ "cli", "core", "json", "log", "reactor", "schema" }) do
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

local cli = require("hecate.cli")

--- The platform as `<os>-<architecture>`, from the path separator, the environment and `uname`.
local function platform()
  if package.config:sub(1, 1) == "\\" then
    local architecture = (os.getenv("PROCESSOR_ARCHITECTURE") or "x86_64"):lower()
    return "windows-" .. (architecture == "amd64" and "x86_64" or architecture)
  end
  local handle = io.popen("uname -sm 2>/dev/null")
  local line = handle and handle:read("l") or nil
  if handle then handle:close() end
  local system, machine = (line or ""):match("^(%S+)%s+(%S+)")
  if not system then return "unknown" end
  return system:lower() .. "-" .. (machine == "arm64" and "aarch64" or machine)
end

local libuv_ok, luv = pcall(require, "luv")
local libuv_version = libuv_ok and luv.version_string and luv.version_string() or nil

--- The version of the LuaRocks on the path (`luarocks --version`), nil when there is none.
local function luarocks_version()
  local handle = io.popen("luarocks --version 2>" .. (package.config:sub(1, 1) == "\\" and "nul" or "/dev/null"))
  local line = handle and handle:read("l") or nil
  if handle then handle:close() end
  return line and line:match("(%d+%.%d+%.%d+)") or nil
end

--- The absolute path of the current directory with forward slashes (`pwd`, `cd` on Windows).
local function current_directory()
  local windows = package.config:sub(1, 1) == "\\"
  local handle = io.popen(windows and "cd" or "pwd")
  local line = handle and handle:read("l") or nil
  if handle then handle:close() end
  return line and (line:gsub("\\", "/")) or nil
end

--- The exact version of the Lua that runs this script (`5.5.1`): the interpreter prints it with `-v`; `_VERSION` only
--- has the line (`5.5`), which is the fallback when the interpreter cannot be asked.
local function lua_release()
  local line = _VERSION:match("%d+%.%d+") or _VERSION
  local interpreter = arg[-1]
  if interpreter then
    local handle = io.popen('"' .. interpreter .. '" -v 2>&1')
    local output = handle and handle:read("l") or nil
    if handle then handle:close() end
    local release = output and output:match("^Lua (%d+%.%d+%.%d+)")
    if release and release:sub(1, #line) == line then return release end
  end
  return line
end

local code = cli.run(arg, {
  commands = cli.commands,
  runtime = {
    hecate_version = "0.0.0",
    lua_version = lua_release(),
    libuv_version = libuv_version,
    luarocks_version = luarocks_version(),
    platform = platform(),
    project_dir = current_directory(),
  },
})
os.exit(code)
