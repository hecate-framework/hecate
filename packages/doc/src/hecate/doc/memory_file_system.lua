-- An in-memory file system: files are strings keyed by normalised path, directories are
-- implied by the files below them. Used by the tests and by embedders.
global <const> require, table, string, pairs, ipairs, type, error

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

local MAX_HOPS = 40 -- links followed while resolving one path (a cycle ends here, like ELOOP)

--- Creates a file system holding `files` (path to content).
---@param files? table<string, string>
function MemoryFileSystem:init(files)
  self.files = {}
  self.links = {} -- normalised path of a link to the normalised path it points to (may not exist: a dangling link)
  for path, data in pairs(files or {}) do self.files[normalise(path)] = data end
end

--- Models a symbolic link: `path` points to `target`. Like a real one it is followed by `read`, `write`, `list` and
--- `exists` (a write through a dangling link creates the target), is reported by `list` with `is_link`, and is only
--- unlinked by `remove_tree`.
---@param path string
---@param target string
function MemoryFileSystem:link(path, target)
  self.links[normalise(path)] = normalise(target)
end

-- The real path of `key`: every link met on the way is replaced by its target (a path of this tree); the last segment
-- is kept as it is when `keep_last` (to ask about the link itself). A cycle gives nil.
local function resolve(self, key, keep_last)
  for _ = 1, MAX_HOPS do
    local parts = {}
    for segment in key:gmatch("[^/]+") do parts[#parts + 1] = segment end
    local replaced, prefix = false, ""
    for index, segment in ipairs(parts) do
      prefix = prefix == "" and segment or (prefix .. "/" .. segment)
      local target = self.links[prefix]
      if target and not (keep_last and index == #parts) then
        key = normalise(target .. "/" .. table.concat(parts, "/", index + 1))
        replaced = true
        break
      end
    end
    if not replaced then return key end
  end
  return nil
end

---@param path string
---@return string?
function MemoryFileSystem:read(path)
  local key = resolve(self, normalise(path))
  return key and self.files[key] or nil
end

---@param path string
---@param data string
function MemoryFileSystem:write(path, data)
  if type(data) ~= "string" then
    error(core.ArgumentError("doc.MemoryFileSystem.write: expects the content as a string"), 2)
  end
  local key = resolve(self, normalise(path))
  if key == nil then error(core.ArgumentError("doc.MemoryFileSystem.write: too many levels of symbolic links: " .. path), 2) end
  self.files[key] = data
end

---@param path string
---@return boolean
function MemoryFileSystem:exists(path)
  local key = resolve(self, normalise(path))
  if key == nil then return false end
  if self.files[key] ~= nil then return true end
  return self:list(path) ~= nil
end

--- Tells whether `path` is itself a link (the links above it are followed).
---@param path string
---@return boolean
function MemoryFileSystem:is_link(path)
  local key = resolve(self, normalise(path), true)
  return key ~= nil and self.links[key] ~= nil
end

-- Whether a directory exists at the real path `key` (a file lies below it).
local function is_directory(self, key)
  local prefix = key == "" and "" or key .. "/"
  for path in pairs(self.files) do
    if path:sub(1, #prefix) == prefix and #path > #prefix then return true end
  end
  for link in pairs(self.links) do
    if link:sub(1, #prefix) == prefix and #link > #prefix then return true end
  end
  return false
end

---@param directory string
---@return hecate.doc.DirectoryEntry[]?
function MemoryFileSystem:list(directory)
  local real = resolve(self, normalise(directory))
  if real == nil then return nil end
  local prefix = real == "" and "" or real .. "/"
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
  for link in pairs(self.links) do
    if link:sub(1, #prefix) == prefix and #link > #prefix then
      local rest = link:sub(#prefix + 1)
      local name, tail = rest:match("^([^/]+)(.*)$")
      if tail == "" then
        local resolved = resolve(self, link)
        local entry = seen[name]
        if entry == nil then
          entry = { name = name }
          entries[#entries + 1] = entry
          seen[name] = entry
        end
        -- A link to a directory is a directory, a link to a file (or a dangling one) is a file.
        entry.is_directory = resolved ~= nil and is_directory(self, resolved) or false
        entry.is_link = true
      elseif not seen[name] then
        seen[name] = true
        entries[#entries + 1] = { name = name, is_directory = true }
      end
    end
  end
  for _, entry in ipairs(entries) do
    if entry.is_link == nil then entry.is_link = false end
  end
  if #entries == 0 then return nil end
  table.sort(entries, function(a, b) return a.name < b.name end)
  return entries
end

--- Removes a directory and everything below it, or a file. A link at `path` is unlinked: its target stays.
---@param path string
function MemoryFileSystem:remove_tree(path)
  local key = resolve(self, normalise(path), true)
  if key == nil then return end
  if self.links[key] then
    self.links[key] = nil
    return
  end
  local prefix = key == "" and "" or key .. "/"
  for file in pairs(self.files) do
    if file == key or file:sub(1, #prefix) == prefix then self.files[file] = nil end
  end
  for link in pairs(self.links) do
    if link:sub(1, #prefix) == prefix then self.links[link] = nil end
  end
end

return core.finalise(MemoryFileSystem)
