-- The real file system over `hecate.reactor.fs` (libuv): portable, no shell, no platform
-- branch (OQ-33, alternative (b)). Every method suspends, so the builder that uses it
-- runs inside a reactor (`reactor.run`), which the runners in `bin/` do.
global <const> require, table, error, tostring, pcall, ipairs, pairs

local core = require("hecate.core")
local reactor = require("hecate.reactor")
local FileSystem = require("hecate.doc.file_system")
local errors = require("hecate.doc.errors")

local fs = reactor.fs

---@class hecate.doc.SystemFileSystem : hecate.doc.FileSystem
---@overload fun(): hecate.doc.SystemFileSystem
local SystemFileSystem = core.class("SystemFileSystem", nil, { implements = { FileSystem } })

--- Creates the file system accessor.
function SystemFileSystem:init()
  self._made = {} -- directories already created by this instance
end

local function build_error(message, path, cause)
  return errors.BuildError({ message = message .. ": " .. tostring(cause), context = { path = path } })
end

local function is_directory(path)
  local status = fs.stat(path)
  return status ~= nil and status.type == "directory"
end

--- `mkdir -p`: creates `path` and the missing parents.
local function make_directory(self, path)
  if path == "" or self._made[path] then return end
  local parent = path:match("^(.*)/[^/]+$")
  if parent and parent ~= "" and not parent:match("^%a:$") then make_directory(self, parent) end
  local ok, err = pcall(fs.mkdir, path)
  if not ok and not is_directory(path) then
    error(build_error("cannot create directory " .. path, path, err), 0)
  end
  self._made[path] = true
end

---@param path string
---@return string?
function SystemFileSystem:read(path)
  local status = fs.stat(path)
  if status == nil or status.type == "directory" then return nil end
  local ok, data = pcall(fs.read_file, path)
  if not ok then error(build_error("cannot read " .. path, path, data), 0) end
  return data
end

---@param path string
---@param data string
function SystemFileSystem:write(path, data)
  make_directory(self, path:match("^(.*)/[^/]*$") or "")
  local ok, err = pcall(fs.write_file, path, data)
  if not ok then error(build_error("cannot write " .. path, path, err), 0) end
end

---@param directory string
---@return hecate.doc.DirectoryEntry[]?
function SystemFileSystem:list(directory)
  if not is_directory(directory) then return nil end
  local entries = {}
  for _, entry in ipairs(fs.list(directory)) do
    local directory_entry = entry.type == "directory"
    if entry.type == "link" then directory_entry = is_directory(directory .. "/" .. entry.name) end
    entries[#entries + 1] = { name = entry.name, is_directory = directory_entry }
  end
  table.sort(entries, function(a, b) return a.name < b.name end)
  return entries
end

---@param path string
---@return boolean
function SystemFileSystem:exists(path)
  return fs.stat(path) ~= nil
end

local function remove_below(path)
  for _, entry in ipairs(fs.list(path)) do
    local child = path .. "/" .. entry.name
    if entry.type == "directory" then
      remove_below(child)
      fs.rmdir(child)
    else
      fs.remove(child)
    end
  end
end

---@param path string
function SystemFileSystem:remove_tree(path)
  if path == "" or path == "/" or path == "." or path == ".." then
    error(core.ArgumentError("doc.SystemFileSystem.remove_tree: refusing to remove " .. ("%q"):format(path)), 2)
  end
  if fs.stat(path) ~= nil then
    local ok, err
    if is_directory(path) then
      ok, err = pcall(function()
        remove_below(path)
        fs.rmdir(path)
      end)
    else
      ok, err = pcall(fs.remove, path)
    end
    if not ok then error(build_error("cannot remove " .. path, path, err), 0) end
  end
  for made in pairs(self._made) do
    if made == path or made:sub(1, #path + 1) == path .. "/" then self._made[made] = nil end
  end
end

return core.finalise(SystemFileSystem)
