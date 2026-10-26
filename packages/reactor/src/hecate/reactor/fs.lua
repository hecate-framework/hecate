-- File-system operations as suspending calls over libuv's asynchronous file API
-- (concurrency.md, "Blocking work"). Failures raise `hecate.reactor.IoError`.
global <const> type, error, require, table, pcall, tostring

local core = require("hecate.core")
local uv = require("luv")
local uv_call = require("hecate.reactor.internal.uv_call")

local CHUNK = 64 * 1024

--- File-system operations that suspend instead of blocking the reactor.
---@class hecate.reactor.fs
local fs = {}

---@param name string
---@param value any
local function require_path(name, value)
  if type(value) ~= "string" then
    error(core.ArgumentError(("%s: expects a path string, got %s"):format(name, type(value))), 3)
  end
end

--- Reads a whole file.
---@async
---@param path string
---@return string
function fs.read_file(path)
  require_path("reactor.read_file", path)
  local fd = uv_call.request("reactor.read_file", "open " .. path, function(cb) uv.fs_open(path, "r", 438, cb) end)
  local parts, offset = {}, 0
  local ok, err = pcall(function()
    while true do
      local chunk = uv_call.request("reactor.read_file", "read " .. path, function(cb) uv.fs_read(fd, CHUNK, offset, cb) end)
      if chunk == nil or #chunk == 0 then return end
      parts[#parts + 1] = chunk
      offset = offset + #chunk
    end
  end)
  uv_call.request("reactor.read_file", "close " .. path, function(cb) uv.fs_close(fd, cb) end)
  if not ok then error(err, 0) end
  return table.concat(parts)
end

--- Writes `data` to a file, creating or truncating it.
---@async
---@param path string
---@param data string
function fs.write_file(path, data)
  require_path("reactor.write_file", path)
  if type(data) ~= "string" then
    error(core.ArgumentError(("reactor.write_file: expects a string, got %s"):format(type(data))), 2)
  end
  local fd = uv_call.request("reactor.write_file", "open " .. path, function(cb) uv.fs_open(path, "w", 438, cb) end)
  local ok, err = pcall(function()
    local offset = 0
    while offset < #data do
      local written = uv_call.request("reactor.write_file", "write " .. path, function(cb)
        uv.fs_write(fd, data:sub(offset + 1), offset, cb)
      end)
      offset = offset + written
    end
  end)
  uv_call.request("reactor.write_file", "close " .. path, function(cb) uv.fs_close(fd, cb) end)
  if not ok then error(err, 0) end
end

--- Returns the status of a path (`type`, `size`, `mtime`, ...), or nil if it does not exist.
---@async
---@param path string
---@return table?
function fs.stat(path)
  require_path("reactor.stat", path)
  uv_call.begin("reactor.stat")
  local missing = false
  local ok, result = pcall(uv_call.request, "reactor.stat", "stat " .. path, function(cb) uv.fs_stat(path, cb) end)
  if ok then return result end
  if core.is_instance_of(result, uv_call.IoError) and result.context.errno == "ENOENT" then
    missing = true
  end
  if missing then return nil end
  error(result, 0)
end

--- Removes a file.
---@async
---@param path string
function fs.remove(path)
  require_path("reactor.remove", path)
  uv_call.request("reactor.remove", "unlink " .. path, function(cb) uv.fs_unlink(path, cb) end)
end

--- Creates a directory.
---@async
---@param path string
function fs.mkdir(path)
  require_path("reactor.mkdir", path)
  uv_call.request("reactor.mkdir", "mkdir " .. path, function(cb) uv.fs_mkdir(path, 511, cb) end)
end

--- Removes an empty directory.
---@async
---@param path string
function fs.rmdir(path)
  require_path("reactor.rmdir", path)
  uv_call.request("reactor.rmdir", "rmdir " .. path, function(cb) uv.fs_rmdir(path, cb) end)
end

--- Lists the entries of a directory as `{ name = string, type = string }` records.
---@async
---@param path string
---@return { name: string, type: string }[]
function fs.list(path)
  require_path("reactor.list", path)
  local handle = uv_call.request("reactor.list", "scandir " .. path, function(cb) uv.fs_scandir(path, cb) end)
  local entries = {}
  while true do
    local name, kind = uv.fs_scandir_next(handle)
    if name == nil then break end
    entries[#entries + 1] = { name = name, type = kind }
  end
  return entries
end

return fs
