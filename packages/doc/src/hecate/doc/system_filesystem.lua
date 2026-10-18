-- The real file system through the standard library: files with `io`, directories with
-- the platform shell (`ls`, `dir`, `mkdir`, `rm`, `rmdir`), because Lua has no directory
-- API and `hecate.reactor.fs` (libuv) would make a batch tool depend on a running reactor
-- and on `luv` (OQ-33). All platform-specific code of the package is in this file.
-- Verified on Linux only until CI runs it on macOS and Windows.
global <const> require, io, os, table, string, package, pairs, error, tostring

local core = require("hecate.core")
local FileSystem = require("hecate.doc.filesystem")
local errors = require("hecate.doc.errors")

local is_windows = package.config:sub(1, 1) == "\\"

---@class hecate.doc.SystemFileSystem : hecate.doc.FileSystem
---@overload fun(): hecate.doc.SystemFileSystem
local SystemFileSystem = core.class("SystemFileSystem", nil, { implements = { FileSystem } })

--- Creates the file system accessor.
function SystemFileSystem:init()
  self._made = {} -- directories already created by this instance
end

local function quote(path)
  if is_windows then return '"' .. path:gsub("/", "\\"):gsub('"', '""') .. '"' end
  return "'" .. path:gsub("'", "'\\''") .. "'"
end

local function capture(command)
  if is_windows then command = '"' .. command .. '"' end
  local pipe = io.popen(command, "r")
  if not pipe then return "", false end
  local output = pipe:read("a")
  local ok = pipe:close()
  return output, ok == true
end

local function run(command)
  local ok = os.execute(is_windows and ('"' .. command .. '"') or command)
  return ok == true
end

local function make_directory(self, path)
  if path == "" or self._made[path] then return end
  local command = is_windows and ("mkdir %s >nul 2>&1"):format(quote(path))
    or ("mkdir -p %s >/dev/null 2>&1"):format(quote(path))
  if not run(command) and not self:list(path) then
    error(errors.BuildError({ message = "cannot create directory " .. path, context = { path = path } }), 0)
  end
  self._made[path] = true
end

---@param path string
---@return string?
function SystemFileSystem:read(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local data = file:read("a")
  file:close()
  return data
end

---@param path string
---@param data string
function SystemFileSystem:write(path, data)
  make_directory(self, path:match("^(.*)/[^/]*$") or "")
  local file, message = io.open(path, "wb")
  if not file then
    error(errors.BuildError({ message = "cannot write " .. path .. ": " .. tostring(message), context = { path = path } }), 0)
  end
  file:write(data)
  file:close()
end

---@param directory string
---@return hecate.doc.DirectoryEntry[]?
function SystemFileSystem:list(directory)
  local entries = {}
  if is_windows then
    local names, ok = capture(("dir /b /a:d %s 2>nul"):format(quote(directory)))
    for name in names:gmatch("[^\r\n]+") do entries[#entries + 1] = { name = name, is_directory = true } end
    local files, files_ok = capture(("dir /b /a:-d %s 2>nul"):format(quote(directory)))
    for name in files:gmatch("[^\r\n]+") do entries[#entries + 1] = { name = name, is_directory = false } end
    if not ok and not files_ok then return nil end
  else
    local output, ok = capture(("ls -1Ap %s 2>/dev/null"):format(quote(directory)))
    if not ok then return nil end
    for name in output:gmatch("[^\n]+") do
      local directory_name = name:match("^(.*)/$")
      entries[#entries + 1] = { name = directory_name or name, is_directory = directory_name ~= nil }
    end
  end
  table.sort(entries, function(a, b) return a.name < b.name end)
  return entries
end

---@param path string
---@return boolean
function SystemFileSystem:exists(path)
  local file = io.open(path, "rb")
  if file then
    file:close()
    return true
  end
  return self:list(path) ~= nil
end

---@param path string
function SystemFileSystem:remove_tree(path)
  if path == "" or path == "/" or path == "." or path == ".." then
    error(core.ArgumentError("refusing to remove " .. ("%q"):format(path)), 2)
  end
  run(is_windows and ("rmdir /s /q %s >nul 2>&1"):format(quote(path)) or ("rm -rf %s"):format(quote(path)))
  for made in pairs(self._made) do
    if made == path or made:sub(1, #path + 1) == path .. "/" then self._made[made] = nil end
  end
end

return core.finalise(SystemFileSystem)
