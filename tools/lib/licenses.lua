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
---@param licence_files? table<string, string[]>  other files that hold the licence of a directory (`M.licence_files`)
---@return string[]
function M.check(dirs, exists, notices, unrecorded, licence_files)
  local problems = {}
  local paths = M.paths(notices)
  for _, dir in ipairs(unrecorded or {}) do
    problems[#problems + 1] = dir .. ": third-party directory without a VENDORED.md (upstream, version, licence)"
  end
  for _, dir in ipairs(dirs) do
    local licensed = exists(dir .. "/LICENSE")
    for _, name in ipairs((licence_files or {})[dir] or {}) do licensed = licensed or exists(dir .. "/" .. name) end
    if not licensed then problems[#problems + 1] = dir .. ": LICENSE file is missing" end
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

--- The top-level files of a digest table that hold a licence text: `LICENSE*`, `LICENCE*` or `OFL-*` (the SIL Open Font License
--- text that the font packages ship). Their digests are verified, so they exist and are the upstream text.
---@param digests { file: string, sha256: string }[]
---@return string[]
function M.licence_files(digests)
  local names = {}
  for _, entry in ipairs(digests) do
    -- Only the top level of the directory: a licence file of a subdirectory belongs to that subdirectory.
    if not entry.file:find("/", 1, true) and (entry.file:find("^LICEN[CS]E") or entry.file:find("^OFL%-")) then
      names[#names + 1] = entry.file
    end
  end
  return names
end

--- The `File | SHA-256` table of a VENDORED.md: one entry per row whose cells are a file name and a run of hexadecimal
--- digits, both in backquotes. An entry whose run is not 64 digits long is kept with `malformed = true`, so that `verify`
--- names the row instead of the row silently going unchecked.
---@param text string content of VENDORED.md
---@return { file: string, sha256: string, malformed: boolean? }[]
function M.digests(text)
  local found = {}
  -- One row per line, and the whole line: the last two cells of the four-cell rows of the npm provenance tables
  -- (`check-vendored`) are not a file and its digest.
  for line in text:gmatch("[^\r\n]+") do
    local file, digest = line:match("^%s*|%s*`([^`|]+)`%s*|%s*`(%x+)`%s*|%s*$")
    if file then found[#found + 1] = { file = file, sha256 = digest:lower(), malformed = #digest ~= 64 or nil } end
  end
  return found
end

--- Problems of the digests of one vendored directory: a listed file that is missing or whose SHA-256 differs
--- from the table (the vendored copy must stay byte-identical to upstream), a row whose digest is not 64 hexadecimal
--- digits, a file listed twice, and a VENDORED.md without a table.
---@param dir string vendored directory, relative to the repository root
---@param digests { file: string, sha256: string, malformed: boolean? }[]
---@param read fun(path: string): string?
---@param hash fun(data: string): string
---@return string[]
function M.verify(dir, digests, read, hash)
  local problems = {}
  if #digests == 0 then
    problems[#problems + 1] = dir .. "/VENDORED.md: no `File | SHA-256` table"
  end
  local seen = {}
  for _, entry in ipairs(digests) do
    local path = dir .. "/" .. entry.file
    local data = read(path)
    if seen[entry.file] then
      problems[#problems + 1] = path .. ": listed twice in VENDORED.md"
    elseif entry.malformed then
      problems[#problems + 1] = ("%s: the SHA-256 recorded in VENDORED.md has %d digits, not 64"):format(path, #entry.sha256)
    elseif data == nil then
      problems[#problems + 1] = path .. ": listed in VENDORED.md but missing"
    elseif hash(data) ~= entry.sha256 then
      problems[#problems + 1] = path .. ": SHA-256 differs from the one recorded in VENDORED.md"
    end
    seen[entry.file] = true
  end
  return problems
end

--- `verify` of the table found in the text of a VENDORED.md (what `check-licenses` and `check-vendored` both run).
---@param dir string
---@param text string content of VENDORED.md
---@param read fun(path: string): string?
---@param hash fun(data: string): string
---@return string[]
function M.verify_text(dir, text, read, hash) return M.verify(dir, M.digests(text), read, hash) end

return M
