-- Entries of `packages/<package>/tests/external.lua` that are a file at a URL (`fetch-fixtures`): the content is
-- pinned by its SHA-256, so the host (a version directory of unicode.org, whose files never change once published)
-- need not be a git repository. An entry with `repository` and `commit` is fetched with git (see the task).
local sha256 = require("lib.sha256")
local util = require("lib.util")

local M = {}

--- The default limit, in bytes, of one downloaded file (`curl --max-filesize`, and a check of the size on disk before the
--- file is read whole and hashed in Lua). An entry raises or lowers it with `max_bytes`.
M.MAX_BYTES = 16 * 1024 * 1024

--- The kind of an entry: "file" (`url` and `sha256`), "git" (`repository` and `commit`), or nil when it is neither,
--- or both (an entry says one thing).
---@param entry table
---@return string?
function M.kind(entry)
  local file = entry.url and entry.sha256
  local git = entry.repository and entry.commit
  if file and not entry.repository then return "file" end
  if git and not entry.url then return "git" end
  return nil
end

--- The problem of an `https` URL given to curl or git, or nil. The text goes into a shell command line: `cmd.exe`
--- expands `%` and treats `^` as its escape character even inside double quotes, and a quote, a space or a line break
--- ends the argument, so none of them is accepted (a legitimate URL percent-encodes them, which a pin does not need).
---@param url any
---@return string?
function M.url_problem(url)
  if type(url) ~= "string" or not url:find("^https://") then return "the url must start with https://" end
  if url:find("[%%%^\"'%s%c]") then
    return "the url must not hold %, ^, a quote, a space or a control character"
  end
  return nil
end

--- Problems of the shape of an entry: a name that stays inside the fixtures directory, and for the file kind an
--- `https` URL and a SHA-256 of 64 lowercase hexadecimal digits, for the git kind an `https` repository and a commit
--- of 40 (SHA-1) or 64 (SHA-256 object format) hexadecimal digits; an optional `max_bytes` is a positive integer.
---@param entry table
---@return string[]
function M.problems(entry)
  local problems = {}
  local name = tostring(entry.name)
  if type(entry.name) ~= "string" or entry.name == "" or entry.name:find("[/\\]") or entry.name:find("^%.")
    or entry.name:find("%c") then
    problems[#problems + 1] = name .. ": the name must be a file name without a directory part"
  end
  local kind = M.kind(entry)
  if kind == "file" then
    local problem = M.url_problem(entry.url)
    if problem then problems[#problems + 1] = name .. ": " .. problem end
    if type(entry.sha256) ~= "string" or not entry.sha256:match("^%x+$") or #entry.sha256 ~= 64
      or entry.sha256 ~= entry.sha256:lower() then
      problems[#problems + 1] = name .. ": sha256 must be 64 lowercase hexadecimal digits"
    end
  elseif kind == "git" then
    local problem = M.url_problem(entry.repository)
    if problem then problems[#problems + 1] = name .. ": " .. problem:gsub("^the url", "the repository") end
    if type(entry.commit) ~= "string" or not entry.commit:match("^%x+$") or (#entry.commit ~= 40 and #entry.commit ~= 64) then
      problems[#problems + 1] = name .. ": commit must be 40 or 64 hexadecimal digits"
    end
  else
    problems[#problems + 1] = name .. ": an entry needs repository and commit, or url and sha256 (not both)"
  end
  if entry.max_bytes ~= nil and not (math.type(entry.max_bytes) == "integer" and entry.max_bytes > 0) then
    problems[#problems + 1] = name .. ": max_bytes must be a positive integer"
  end
  return problems
end

-- One argument for the shell. `util.quote` turns "/" into "\\" on Windows (it quotes paths); a URL keeps its slashes.
local function word(text)
  if util.is_windows() then return '"' .. text .. '"' end
  return "'" .. text:gsub("'", "'\\''") .. "'"
end
M.word = word

--- Downloads `url` to `path` with curl (on Linux, macOS and Windows 10 and later). Only `https` is allowed, for the
--- request and for every redirect (`--proto`, `--proto-redir`: an https URL cannot send the request on to http), and a
--- file larger than `max_bytes` (default `M.MAX_BYTES`) is refused. Returns the output and success.
---@param url string
---@param path string
---@param max_bytes? integer
---@return string output
---@return boolean ok
function M.download(url, path, max_bytes)
  local problem = M.url_problem(url)
  if problem then return problem, false end
  return util.capture(("curl --fail --silent --show-error --location --proto %s --proto-redir %s --max-filesize %d --max-time 120 --output %s %s 2>&1")
    :format(word("=https"), word("=https"), max_bytes or M.MAX_BYTES, util.quote(path), word(url)))
end

--- The size of a file in bytes, or nil when it cannot be opened.
---@param path string
---@return integer?
function M.size(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local size = f:seek("end")
  f:close()
  return size
end

-- The whole file, or nil when it is absent or larger than `max` (it is read whole, so the size is checked first).
local function read(path, max)
  local f = io.open(path, "rb")
  if not f then return nil end
  local size = f:seek("end")
  local data
  if size <= max then
    f:seek("set")
    data = f:read("a")
  end
  f:close()
  return data
end

--- Makes sure `directory/<entry.name>` holds the content pinned by `entry.sha256`. Returns the state, "cached" (already
--- there and matching) or "fetched", or nil and the problem. No file that the pin does not describe stays where a test
--- would read it: a stale file is deleted when the download fails, is empty, is too large or does not match, and a
--- leftover `.part` is removed first. `download(url, path, max_bytes)` is injectable.
---@param entry table
---@param directory string
---@param download? fun(url: string, path: string, max_bytes: integer): string, boolean
---@param retry? fun(step: fun(): string, boolean): string, boolean
---@return string? state
---@return string? problem
function M.ensure(entry, directory, download, retry)
  local shape = M.problems(entry)
  if #shape > 0 then return nil, shape[1] end
  if M.kind(entry) ~= "file" then return nil, tostring(entry.name) .. ": not an entry of the file kind" end
  download = download or M.download
  local max = entry.max_bytes or M.MAX_BYTES
  local path = directory .. "/" .. entry.name
  local data = read(path, max)
  if data and sha256.hex(data) == entry.sha256 then return "cached" end
  util.mkdir(directory)
  local partial = path .. ".part"
  os.remove(partial)
  local function refuse(message)
    os.remove(partial)
    os.remove(path)
    return nil, ("%s: %s"):format(entry.name, message)
  end
  local function step() return download(entry.url, partial, max) end
  local out, ok
  if retry then out, ok = retry(step) else out, ok = step() end
  if not ok then return refuse(("cannot download %s: %s"):format(entry.url, out)) end
  local size = M.size(partial)
  if not size or size == 0 then return refuse(("the download of %s is empty"):format(entry.url)) end
  if size > max then return refuse(("%s is larger than %d bytes"):format(entry.url, max)) end
  local got = read(partial, max)
  local actual = got and sha256.hex(got)
  if actual ~= entry.sha256 then
    return refuse(("sha256 of %s is %s, pinned %s"):format(entry.url, tostring(actual), entry.sha256))
  end
  os.remove(path) -- rename does not replace an existing file on Windows
  assert(os.rename(partial, path))
  return "fetched"
end

return M
