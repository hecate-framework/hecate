-- Installs the git hooks: lua tools/hooks/install.lua
-- Writes small shell shims into .git/hooks that run tools/hooks/<hook>.lua with the Lua
-- interpreter that ran this installer. Existing hooks not written by us are kept as
-- <hook>.backup and never overwritten silently.
local script = arg[0]:gsub("\\", "/")
local hooks_dir = script:match("^(.*)/[^/]*$") or "."
package.path = hooks_dir .. "/../?.lua;" .. hooks_dir .. "/../lib/?.lua;" .. package.path
local util = require("lib.util")

local MARK = "# hecate-hook"
local root = util.capture("git rev-parse --show-toplevel")
if root == "" then io.stderr:write("install: not inside a git repository\n") os.exit(1) end
local git_hooks = util.capture("git rev-parse --git-path hooks")
if not git_hooks:find("^/") and not git_hooks:find("^%a:") then git_hooks = root .. "/" .. git_hooks end
util.mkdir(git_hooks)

local lua = util.interpreter():gsub("\\", "/")
if not lua:find("[/]") then lua = util.capture(util.is_windows() and "where " .. lua or "command -v " .. lua):match("[^\r\n]+") or lua end
lua = lua:gsub("\\", "/")

for _, hook in ipairs({ "pre-commit", "commit-msg" }) do
  local path = git_hooks .. "/" .. hook
  local existing = io.open(path, "rb")
  if existing then
    local body = existing:read("a")
    existing:close()
    if not body:find(MARK, 1, true) then
      os.rename(path, path .. ".backup")
      print(("install: kept existing %s as %s.backup"):format(hook, hook))
    end
  end
  local f = assert(io.open(path, "wb"))
  f:write("#!/bin/sh\n", MARK, "\n")
  f:write(("exec '%s' '%s/tools/hooks/%s.lua' \"$@\"\n"):format(lua, root, hook))
  f:close()
  if not util.is_windows() then os.execute("chmod +x '" .. path .. "'") end
  print("install: " .. hook)
end
