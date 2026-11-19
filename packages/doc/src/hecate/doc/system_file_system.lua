-- The real file system over `hecate.reactor.fs` (libuv): portable, no shell, no platform
-- branch (OQ-33, alternative (b)). Every method suspends, so the builder that uses it
-- runs inside a reactor (`reactor.run`), which the runners in `bin/` do.
global <const> require, table, error, tostring, pcall, ipairs, pairs

local core = require("hecate.core")
local reactor = require("hecate.reactor")
local FileSystem = require("hecate.doc.file_system")
local errors = require("hecate.doc.errors")
local paths = require("hecate.doc.internal.paths")

local fs = reactor.fs
local WINDOWS = paths.is_windows()

-- On Windows `\` separates paths and the code below works with `/` only: it is replaced once, at every entry point. On
-- another platform `\` is a letter of a file name and is left alone.
local function native(path)
  if WINDOWS then return paths.separators(path) end
  return path
end

-- What libuv calls a link: `stat` of the entry in its directory (no link followed) reports `link` for a symbolic link,
-- and, on Windows, for a junction (a reparse point); `junction` is accepted as well, should a version report it.
local LINK_TYPES = { link = true, junction = true }

---@class hecate.doc.SystemFileSystem : hecate.doc.FileSystem
---@overload fun(): hecate.doc.SystemFileSystem
local SystemFileSystem = core.class("SystemFileSystem", nil, { implements = { FileSystem } })

--- Creates the file system accessor.
function SystemFileSystem:init()
  self._made = {} -- directories already created by this instance
end

local function build_error(message, path, cause)
  return errors.BuildError({ message = "doc.SystemFileSystem: " .. message .. ": " .. tostring(cause), context = { path = path } })
end

local function is_directory(path)
  local status = fs.stat(path)
  return status ~= nil and status.type == "directory"
end

--- `mkdir -p`: creates `path` and the missing parents.
local function make_directory(self, path)
  if path == "" or self._made[path] then return end
  local parent = path:match("^(.*)/[^/]+$")
  -- The parent of a drive (`C:`) or of a network share (`//server/share`) is not created: it is the root.
  if parent and parent ~= "" and not parent:match("^%a:$") and not paths.is_root(parent) then make_directory(self, parent) end
  local ok, err = pcall(fs.mkdir, path)
  if not ok and not is_directory(path) then
    error(build_error("cannot create directory " .. path, path, err), 0)
  end
  self._made[path] = true
end

---@param path string
---@return string?
function SystemFileSystem:read(path)
  path = native(path)
  local status = fs.stat(path)
  if status == nil or status.type == "directory" then return nil end
  local ok, data = pcall(fs.read_file, path)
  if not ok then error(build_error("cannot read " .. path, path, data), 0) end
  return data
end

---@param path string
---@param data string
function SystemFileSystem:write(path, data)
  path = native(path)
  -- A write through a link would truncate or create the file it points to (a dangling link included): refused.
  if self:is_link(path) then
    error(errors.BuildError({
      message = ("doc.SystemFileSystem: refusing to write %s: it is a symbolic link; remove it or write elsewhere"):format(path),
      context = { path = path },
    }), 0)
  end
  make_directory(self, path:match("^(.*)/[^/]*$") or "")
  local ok, err = pcall(fs.write_file, path, data)
  if not ok then error(build_error("cannot write " .. path, path, err), 0) end
end

---@param directory string
---@return hecate.doc.DirectoryEntry[]?
function SystemFileSystem:list(directory)
  directory = native(directory)
  if not is_directory(directory) then return nil end
  local entries = {}
  for _, entry in ipairs(fs.list(directory)) do
    local directory_entry = entry.type == "directory"
    local link = LINK_TYPES[entry.type] == true
    if link then directory_entry = is_directory(directory .. "/" .. entry.name) end
    entries[#entries + 1] = { name = entry.name, is_directory = directory_entry, is_link = link }
  end
  table.sort(entries, function(a, b) return a.name < b.name end)
  return entries
end

---@param path string
---@return boolean
function SystemFileSystem:exists(path)
  path = native(path)
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

--- Tells whether `path` is itself a symbolic link (`stat` follows links, so the entry is looked up in its parent
--- directory, where it is reported without being followed). A trailing `/` is ignored.
---@param path string
---@return boolean
function SystemFileSystem:is_link(path)
  path = native(path)
  local trimmed = path:gsub("/+$", "")
  local parent, name = trimmed:match("^(.*)/([^/]+)$")
  if not name then parent, name = ".", trimmed end
  if parent == "" then parent = "/" end
  if not is_directory(parent) then return false end
  for _, entry in ipairs(fs.list(parent)) do
    if entry.name == name then return LINK_TYPES[entry.type] == true end
  end
  return false
end

--- Removes a directory tree, or a file. A symbolic link at `path` is unlinked itself: its target is never
--- followed or removed.
---@param path string
function SystemFileSystem:remove_tree(path)
  path = native(path)
  -- The roots of a file system, the current directory and its parent, and the home shorthand are never removed,
  -- whatever way they are written (`a/..`, `C:\`, `\\server\share`, `//server`).
  local normal = paths.normalise(path)
  if path:find("^%s*$") or normal == "." or normal == ".." or normal == "~" or paths.is_root(path) then
    error(core.ArgumentError("doc.SystemFileSystem.remove_tree: refusing to remove " .. ("%q"):format(path)), 2)
  end
  if self:is_link(path) then
    local ok, err = pcall(fs.remove, (path:gsub("/+$", "")))
    if not ok then error(build_error("cannot unlink " .. path, path, err), 0) end
  elseif fs.stat(path) ~= nil then
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
