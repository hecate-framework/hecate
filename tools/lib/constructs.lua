-- Lua 5.5-only constructs permitted by ADR 0001 (pure functions).
-- Allowed: `global <const> *` / `global name` declarations (reads), read-only for variables,
-- named varargs, table.create through hecate.core.compat. Anything else that is 5.5-only is
-- reported: global definitions (library code declares no globals), direct table.create and
-- the incremental/generational `collectgarbage("param")` option.
local M = {}

---@param source string
---@param allow_table_create boolean  true inside hecate.core's compat module
---@return { line: integer, message: string }[]
function M.scan(source, allow_table_create)
  local found, n = {}, 0
  source = source:gsub("%-%-%[(=*)%[.-%]%1%]", function(m) return (m:gsub("[^\n]", "")) end)
  for line in (source .. "\n"):gmatch("(.-)\r?\n") do
    n = n + 1
    local code = line:gsub("%-%-.*$", ""):gsub('"[^"]*"', '""'):gsub("'[^']*'", "''")
    local function add(msg) found[#found + 1] = { line = n, message = msg } end
    if code:match("^%s*global%s+function%f[%W]") then
      add("`global function` defines a global; library code declares no globals (ADR 0001)")
    elseif code:match("^%s*global%s+[%w_<>, ]-=") and not code:match("^%s*global%s+<const>%s*%*") then
      add("`global` definition with initialiser; only read declarations are allowed (ADR 0001)")
    end
    if not allow_table_create and code:find("table%.create%s*%(") then
      add("table.create is 5.5-only; use hecate.core.compat.table_create (ADR 0001)")
    end
    if code:find("collectgarbage%s*%(%s*[\"']param[\"']") then
      add('collectgarbage("param") is 5.5-only and has no allowed lowering (ADR 0001)')
    end
  end
  return found
end

return M
