-- pre-commit hook body: lint the packages with staged Lua sources (format-check is a
-- no-op: no formatter supports Lua 5.5, OQ-3). Invoked by the shim written by install.lua.
local script = arg[0]:gsub("\\", "/")
local hooks_dir = script:match("^(.*)/[^/]*$") or "."
package.path = hooks_dir .. "/../?.lua;" .. hooks_dir .. "/../lib/?.lua;" .. package.path
local util = require("lib.util")

local out = util.capture("git diff --cached --name-only --diff-filter=ACMR")
local packages, seen = {}, {}
for path in out:gmatch("[^\r\n]+") do
  local pkg = path:match("^packages/([^/]+)/src/.*%.lua$")
  if pkg and not seen[pkg] then seen[pkg] = true packages[#packages + 1] = pkg end
end
if #packages == 0 then os.exit(0) end

local run = util.interpreter() .. " " .. util.quote(hooks_dir .. "/../run.lua")
for _, task in ipairs({ "format-check", "lint" }) do
  local cmd = run .. " " .. task
  if task == "lint" then cmd = cmd .. " " .. table.concat(packages, " ") end
  if not os.execute(cmd) then os.exit(1) end
end
os.exit(0)
