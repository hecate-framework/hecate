-- Helpers of the `check-licenses` task: every vendored directory ships its licence, says where it comes from
-- (VENDORED.md) and is recorded in THIRD_PARTY_NOTICES, and every path that file names exists.
local M = {}

--- Directory names that mean "third-party code lives here".
M.vendor_names = { vendor = true, third_party = true }

--- The directory named `vendor` or `third_party` that holds a file, or nil (the shallowest one).
---@param path string relative path of a file
---@return string?
function M.vendor_directory(path)
  local prefix = {}
  for segment in path:gmatch("[^/]+") do
    prefix[#prefix + 1] = segment
    if M.vendor_names[segment] then return table.concat(prefix, "/") end
  end
  return nil
end

--- Paths under `packages/` named by THIRD_PARTY_NOTICES, without the punctuation that ends a sentence.
---@param notices string text of THIRD_PARTY_NOTICES
---@return string[]
function M.paths(notices)
  local found = {}
  for token in notices:gmatch("packages/[%w_%-%./]+") do
    found[#found + 1] = (token:gsub("[%.,;:]+$", ""):gsub("/+$", ""))
  end
  return found
end

--- Problems of the vendored directories (paths relative to the repository root). `dirs` are the directories
--- that hold a VENDORED.md, `unrecorded` the directories named `vendor` or `third_party` without one.
---@param dirs string[]
---@param exists fun(path: string): boolean
---@param notices string text of THIRD_PARTY_NOTICES
---@param unrecorded? string[]
---@return string[]
function M.check(dirs, exists, notices, unrecorded)
  local problems = {}
  local paths = M.paths(notices)
  for _, dir in ipairs(unrecorded or {}) do
    problems[#problems + 1] = dir .. ": third-party directory without a VENDORED.md (upstream, version, licence)"
  end
  for _, dir in ipairs(dirs) do
    if not exists(dir .. "/LICENSE") then problems[#problems + 1] = dir .. ": LICENSE file is missing" end
    local recorded = false
    for _, path in ipairs(paths) do
      if path == dir or path:sub(1, #dir + 1) == dir .. "/" then recorded = true break end
    end
    if not recorded then problems[#problems + 1] = dir .. ": not recorded in THIRD_PARTY_NOTICES" end
  end
  local seen = {}
  for _, path in ipairs(paths) do
    if not seen[path] and not exists(path) then
      problems[#problems + 1] = "THIRD_PARTY_NOTICES names " .. path .. ", which does not exist"
    end
    seen[path] = true
  end
  return problems
end

return M
