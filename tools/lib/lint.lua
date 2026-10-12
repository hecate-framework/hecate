-- Lint rules for library sources (coding-standards.md, "Language level").
-- 1. The chunk compiles (luac -p).
-- 2. It declares its globals with a `global` statement, which makes every other free
--    name a compile-time error in Lua 5.5 (no implicit globals, no global writes).
local util = require("lib.util")

local M = {}

--- Lints one file; returns a list of problem strings.
---@param path string
---@param label string
---@return string[]
function M.check_file(path, label)
  local problems = {}
  local out, ok = util.capture(('luac -p "%s" 2>&1'):format(path))
  if not ok then
    problems[#problems + 1] = out ~= "" and out or (label .. ": does not compile")
    return problems
  end
  local f = assert(io.open(path, "rb"))
  local text = f:read("a")
  f:close()
  if not text:find("^global[ <]") and not text:find("\nglobal[ <]") then
    problems[#problems + 1] = label .. ": no `global` declaration (library chunks declare the globals they read)"
  end
  return problems
end

return M
