-- Helpers of the `check-vendored` task (pure functions): the npm provenance that a VENDORED.md records for the files it
-- vendors, so that the vendored copy can be traced to, and re-verified against, the registry. Standard library only.
--
-- A VENDORED.md records it in two tables next to the `File | SHA-256` table that `check-licenses` verifies:
--
--   | Package | Version | `dist.integrity` | `dist.shasum` |
--   | `mermaid` | `12.3.0` | `sha512-<base64>` | `<40 hexadecimal digits>` |
--
--   | Vendored file | Package | Path in the package |
--   | `mermaid.min.js` | `mermaid` | `dist/mermaid.min.js` |
--
-- `dist.integrity` is the SHA-512 of the tarball (Subresource Integrity form), `dist.shasum` its SHA-1 as the registry
-- prints it (recorded for comparison with `npm view`, not recomputed: the SHA-512 is the strong one). The vendored file
-- is the file at that path of the unpacked tarball (npm unpacks into `package/`), and its SHA-256 is the one of the
-- `File | SHA-256` table.
local M = {}

--- The largest tarball `check-vendored --online` accepts, in bytes (the mermaid tarball is 26 MB).
M.MAX_TARBALL = 64 * 1024 * 1024

local CELL = "%s*`([^`|]+)`%s*|"

-- The cells of the lines that are a whole table row of `count` backquoted cells.
local function rows(text, count)
  local pattern = "^%s*|" .. CELL:rep(count) .. "%s*$"
  local found = {}
  for line in text:gmatch("[^\r\n]+") do
    local cells = { line:match(pattern) }
    if #cells == count then found[#found + 1] = cells end
  end
  return found
end

--- The package rows of the text of a VENDORED.md: `{ name, version, integrity, shasum }` (rows of four backquoted cells
--- whose third cell is a Subresource Integrity string, `sha512-...`).
---@param text string
---@return { name: string, version: string, integrity: string, shasum: string }[]
function M.packages(text)
  local found = {}
  for _, cells in ipairs(rows(text, 4)) do
    if cells[3]:find("^sha%d+%-") then
      found[#found + 1] = { name = cells[1], version = cells[2], integrity = cells[3], shasum = cells[4] }
    end
  end
  return found
end

--- The file rows of the text of a VENDORED.md: `{ file, package, path }` (rows of three backquoted cells).
---@param text string
---@return { file: string, package: string, path: string }[]
function M.files(text)
  local found = {}
  for _, cells in ipairs(rows(text, 3)) do found[#found + 1] = { file = cells[1], package = cells[2], path = cells[3] } end
  return found
end

--- The URL of the tarball of a package on the registry: `https://registry.npmjs.org/<name>/-/<base>-<version>.tgz`
--- where `<base>` is the name without its scope.
---@param name string
---@param version string
---@return string
function M.tarball_url(name, version)
  return ("https://registry.npmjs.org/%s/-/%s-%s.tgz"):format(name, name:match("[^/]+$"), version)
end

--- Whether a path inside a package stays inside it and holds only characters that need no quoting.
---@param path string
---@return boolean
function M.safe_path(path)
  if path == "" or path:find("^/") or path:find("[^%w_%-%./@+]") then return false end
  for segment in path:gmatch("[^/]+") do
    if segment == ".." or segment == "." then return false end
  end
  return true
end

--- Problems of the provenance records of one VENDORED.md. `digests` is the `File | SHA-256` table (`licenses.digests`).
--- A text without any record gives none: not every vendored directory comes from npm.
---@param dir string  the vendored directory, for the messages
---@param text string
---@param digests { file: string, sha256: string }[]
---@return string[]
function M.problems(dir, text, digests)
  local problems = {}
  local packages, files = M.packages(text), M.files(text)
  local where = dir .. "/VENDORED.md"
  local by_name, listed, used = {}, {}, {}
  for _, p in ipairs(packages) do
    local label = ("%s: npm package %s@%s"):format(where, p.name, p.version)
    if not p.name:match("^@?[%w_%-%.]+/?[%w_%-%.]*$") or p.name:find("%.%.") then
      problems[#problems + 1] = ("%s: the package name '%s' is not an npm package name"):format(where, p.name)
    end
    if not p.version:match("^%d+%.%d+%.%d+[%w%.%-+]*$") then
      problems[#problems + 1] = ("%s: the version '%s' of %s is not a version"):format(where, p.version, p.name)
    end
    if not p.integrity:match("^sha512%-[A-Za-z0-9+/]+==$") or #p.integrity ~= 7 + 88 then
      problems[#problems + 1] = label .. ": dist.integrity must be sha512- and the 88 characters of a base64 SHA-512"
    end
    if not p.shasum:match("^%x+$") or #p.shasum ~= 40 or p.shasum ~= p.shasum:lower() then
      problems[#problems + 1] = label .. ": dist.shasum must be 40 lowercase hexadecimal digits"
    end
    if by_name[p.name] then problems[#problems + 1] = ("%s: npm package %s is recorded twice"):format(where, p.name) end
    by_name[p.name] = p
  end
  local digested = {}
  for _, d in ipairs(digests) do digested[d.file] = true end
  for _, f in ipairs(files) do
    if not by_name[f.package] then
      problems[#problems + 1] = ("%s: %s names the package %s, which has no dist.integrity row"):format(where, f.file, f.package)
    end
    if not M.safe_path(f.path) then
      problems[#problems + 1] = ("%s: the path '%s' of %s must stay inside the package"):format(where, f.path, f.file)
    end
    if not digested[f.file] then
      problems[#problems + 1] = ("%s: %s has no row in the File | SHA-256 table"):format(where, f.file)
    end
    if listed[f.file] then problems[#problems + 1] = ("%s: %s is listed twice as an npm file"):format(where, f.file) end
    listed[f.file] = true
    used[f.package] = true
  end
  for _, p in ipairs(packages) do
    if not used[p.name] then problems[#problems + 1] = ("%s: npm package %s records no vendored file"):format(where, p.name) end
  end
  return problems
end

return M
