-- Entries of `packages/<package>/tests/external.lua` that are a file at a URL (`fetch-fixtures`): the content is
-- pinned by its SHA-256, so the host (a version directory of unicode.org, whose files never change once published)
-- need not be a git repository. An entry with `repository` and `commit` is fetched with git (see the task).
local sha256 = require("lib.sha256")
local util = require("lib.util")

local M = {}

--- The kind of an entry: "file" (`url` and `sha256`), "git" (`repository` and `commit`), or nil when it is neither.
---@param entry table
---@return string?
function M.kind(entry)
  if entry.url and entry.sha256 then return "file" end
  if entry.repository and entry.commit then return "git" end
  return nil
end

--- Problems of the shape of an entry of the file kind: a name that stays inside the fixtures directory, an
--- `https` URL and a SHA-256 of 64 lowercase hexadecimal digits.
---@param entry table
---@return string[]
function M.problems(entry)
  local problems = {}
  local name = tostring(entry.name)
  if type(entry.name) ~= "string" or entry.name == "" or entry.name:find("[/\\]") or entry.name:find("^%.") then
    problems[#problems + 1] = name .. ": the name must be a file name without a directory part"
  end
  if M.kind(entry) == "file" then
    if type(entry.url) ~= "string" or not entry.url:find("^https://") then
      problems[#problems + 1] = name .. ": the url must start with https://"
    end
    if type(entry.sha256) ~= "string" or not entry.sha256:match("^%x+$") or #entry.sha256 ~= 64
      or entry.sha256 ~= entry.sha256:lower() then
      problems[#problems + 1] = name .. ": sha256 must be 64 lowercase hexadecimal digits"
    end
  end
  return problems
end

--- Downloads `url` to `path` with curl (on Linux, macOS and Windows 10 and later). Returns the output and success.
---@param url string
---@param path string
---@return string output
---@return boolean ok
function M.download(url, path)
  local quoted = util.is_windows() and ('"' .. url:gsub('"', '""') .. '"') or ("'" .. url:gsub("'", "'\\''") .. "'")
  return util.capture(("curl --fail --silent --show-error --location --max-time 120 --output %s %s 2>&1"):format(util.quote(path), quoted))
end

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("a")
  f:close()
  return data
end

--- Makes sure `directory/<entry.name>` holds the content pinned by `entry.sha256`. Returns the state, "cached" (already
--- there and matching) or "fetched", or nil and the problem. A download that does not match is deleted: no file
--- that the pin does not describe stays where a test would read it. `download(url, path)` is injectable.
---@param entry table
---@param directory string
---@param download? fun(url: string, path: string): string, boolean
---@param retry? fun(step: fun(): string, boolean): string, boolean
---@return string? state
---@return string? problem
function M.ensure(entry, directory, download, retry)
  download = download or M.download
  local path = directory .. "/" .. entry.name
  local data = read(path)
  if data and sha256.hex(data) == entry.sha256 then return "cached" end
  util.mkdir(directory)
  local partial = path .. ".part"
  os.remove(partial)
  local function step() return download(entry.url, partial) end
  local out, ok
  if retry then out, ok = retry(step) else out, ok = step() end
  if not ok then
    os.remove(partial)
    return nil, ("%s: cannot download %s: %s"):format(entry.name, entry.url, out)
  end
  local got = read(partial)
  local actual = got and sha256.hex(got)
  if actual ~= entry.sha256 then
    os.remove(partial)
    os.remove(path)
    return nil, ("%s: sha256 of %s is %s, pinned %s"):format(entry.name, entry.url, tostring(actual), entry.sha256)
  end
  os.remove(path) -- rename does not replace an existing file on Windows
  assert(os.rename(partial, path))
  return "fetched"
end

return M
