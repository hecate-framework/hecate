-- Environment of a child process: the inherited environment plus additions, minus the entries a
-- child must not inherit. Pure (no libuv), so that the Windows rules can be tested everywhere.
global <const> pairs, table

local M = {}

--- Merges `added` into a copy of `inherited` and returns it as sorted `NAME=value` entries.
--- On Windows variable names are case-insensitive: an addition replaces an existing variable of
--- the same name whatever its case, and keeps the existing spelling (`Path` stays `Path`).
---@param inherited table<string, string>  the environment of this process
---@param added table<string, string>  variables to set; they win over `inherited`
---@param case_insensitive boolean  the names compare without regard to case (Windows)
---@param dropped? string  name of an inherited variable to remove (the message pipe marker)
---@return string[] entries
function M.merge(inherited, added, case_insensitive, dropped)
  local function key(name) return case_insensitive and name:lower() or name end
  local merged, spelling = {}, {} -- value and spelling of each variable, by comparison key
  local dropped_key = dropped and key(dropped)
  for name, value in pairs(inherited) do
    if key(name) ~= dropped_key then
      merged[key(name)], spelling[key(name)] = value, name
    end
  end
  for name, value in pairs(added) do
    merged[key(name)] = value
    spelling[key(name)] = spelling[key(name)] or name
  end
  local list = {}
  for compared, value in pairs(merged) do list[#list + 1] = spelling[compared] .. "=" .. value end
  table.sort(list)
  return list
end

return M
