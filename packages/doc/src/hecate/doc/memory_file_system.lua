-- An in-memory file system: files are strings keyed by normalised path, directories are
-- implied by the files below them. Used by the tests and by embedders.
global <const> require, table, string, pairs, type, error

local core = require("hecate.core")
local FileSystem = require("hecate.doc.file_system")

---@class hecate.doc.MemoryFileSystem : hecate.doc.FileSystem
---@field files table<string, string>  path to content (read it to inspect what was written)
---@overload fun(files?: table<string, string>): hecate.doc.MemoryFileSystem
local MemoryFileSystem = core.class("MemoryFileSystem", nil, { implements = { FileSystem } })

local function normalise(path)
  local parts = {}
  for segment in path:gmatch("[^/]+") do
    if segment == ".." then parts[#parts] = nil elseif segment ~= "." then parts[#parts + 1] = segment end
  end
  return table.concat(parts, "/")
end

--- Creates a file system holding `files` (path to content).
---@param files? table<string, string>
function MemoryFileSystem:init(files)
  self.files = {}
  for path, data in pairs(files or {}) do self.files[normalise(path)] = data end
end

---@param path string
---@return string?
function MemoryFileSystem:read(path) return self.files[normalise(path)] end

---@param path string
---@param data string
function MemoryFileSystem:write(path, data)
  if type(data) ~= "string" then
    error(core.ArgumentError("doc.MemoryFileSystem.write: expects the content as a string"), 2)
  end
  self.files[normalise(path)] = data
end

---@param path string
---@return boolean
function MemoryFileSystem:exists(path)
  local key = normalise(path)
  if self.files[key] ~= nil then return true end
  return self:list(path) ~= nil
end

---@param directory string
---@return hecate.doc.DirectoryEntry[]?
function MemoryFileSystem:list(directory)
  local prefix = normalise(directory)
  prefix = prefix == "" and "" or prefix .. "/"
  local seen, entries = {}, {}
  for path in pairs(self.files) do
    if path:sub(1, #prefix) == prefix and #path > #prefix then
      local rest = path:sub(#prefix + 1)
      local name, tail = rest:match("^([^/]+)(.*)$")
      if not seen[name] then
        seen[name] = true
        entries[#entries + 1] = { name = name, is_directory = tail ~= "" }
      end
    end
  end
  if #entries == 0 then return nil end
  table.sort(entries, function(a, b) return a.name < b.name end)
  return entries
end

---@param path string
function MemoryFileSystem:remove_tree(path)
  local key = normalise(path)
  local prefix = key == "" and "" or key .. "/"
  for file in pairs(self.files) do
    if file == key or file:sub(1, #prefix) == prefix then self.files[file] = nil end
  end
end

return core.finalise(MemoryFileSystem)
