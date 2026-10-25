-- Helpers of the `check-licenses` task: every vendored directory ships its licence and is recorded in
-- THIRD_PARTY_NOTICES.
local M = {}

--- Problems of the vendored directories (paths relative to the repository root).
---@param dirs string[]
---@param exists fun(path: string): boolean
---@param notices string text of THIRD_PARTY_NOTICES
---@return string[]
function M.check(dirs, exists, notices)
  local problems = {}
  for _, dir in ipairs(dirs) do
    if not exists(dir .. "/LICENSE") then problems[#problems + 1] = dir .. ": LICENSE file is missing" end
    if not notices:find(dir .. "/", 1, true) then
      problems[#problems + 1] = dir .. ": not recorded in THIRD_PARTY_NOTICES"
    end
  end
  return problems
end

return M
