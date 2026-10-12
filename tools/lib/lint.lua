-- Lint rules for library sources (coding-standards.md, "Language level").
-- 1. The chunk compiles (luac -p).
-- 2. It declares its globals with a `global` statement, which makes every other free
--    name a compile-time error in Lua 5.5 (no implicit globals, no global writes).
local M = {}

--- Lints a chunk given as text; returns a list of problem strings.
---@param text string
---@param label string
---@return string[]
function M.check_source(text, label)
  local _, err = load(text, "=" .. label, "t")
  if err then return { err } end
  if not text:find("^global[ <]") and not text:find("\nglobal[ <]") then
    return { label .. ": no `global` declaration (library chunks declare the globals they read)" }
  end
  return {}
end

--- Lints one file; returns a list of problem strings.
---@param path string
---@param label string
---@return string[]
function M.check_file(path, label)
  local f = io.open(path, "rb")
  if not f then return { label .. ": cannot be read" } end
  local text = f:read("a")
  f:close()
  return M.check_source(text, label)
end

return M
