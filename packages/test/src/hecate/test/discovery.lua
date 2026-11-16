-- Discovery: finds `*_test.lua` files under a directory and loads the case each returns.
global <const> require, table, loadfile, pcall, type, ipairs, error, package

local core = require("hecate.core")
local fs = require("hecate.reactor").fs
local case_module = require("hecate.test.case")

--- Raised when a test file cannot be loaded or does not return a test case.
---@class hecate.test.LoadError : hecate.core.Error
local LoadError = core.error_class("LoadError", "hecate.test.LoadError")

---@class hecate.test.discovery
---@field LoadError hecate.test.LoadError
local M = { LoadError = LoadError }

-- The file each loaded case came from: the default name of its suite (a suite is a test script).
-- A plain table: a loaded case lives as long as the run anyway.
local origins = {}

--- Returns the path a case was loaded from by `load`, or nil for a case declared in code.
---@param case hecate.test.Case
---@return string? path
function M.origin(case) return origins[case] end

--- Returns `path` as it is displayed and joined: on Windows (`separator` is a backslash) the backslashes become
--- forward slashes, which Windows accepts everywhere, so that a suite name reads the same on every platform and
--- never mixes both separators. Elsewhere the path is unchanged (a backslash is an ordinary character of a name).
---@param path string
---@param separator? string  the path separator of the platform (default `package.config:sub(1, 1)`)
---@return string path
function M.display_path(path, separator)
  separator = separator or package.config:sub(1, 1)
  if separator == "\\" then return (path:gsub("\\", "/")) end
  return path
end

--- Returns the paths of the files named `*_test.lua` under `directory`, recursively, sorted.
--- Raises `hecate.core.ArgumentError` when `directory` cannot be read (missing, not a directory, no permission).
---@async
---@param directory string
---@return string[] paths
function M.discover(directory)
  local found = {}
  local root = M.display_path(directory):gsub("/+$", "")
  -- the root must be readable: a mistyped path is an error, not a run without tests
  local ok, entries = pcall(fs.list, root)
  if not ok then
    error(core.ArgumentError("test.discover: the directory cannot be read", { context = { path = root, cause = entries } }), 2)
  end
  local function walk(dir, listed)
    for _, entry in ipairs(listed) do
      local path = dir .. "/" .. entry.name
      if entry.type == "directory" then
        local readable, children = pcall(fs.list, path) -- a subdirectory that cannot be read is skipped
        if readable then walk(path, children) end
      elseif entry.name:find("_test%.lua$") then found[#found + 1] = path end
    end
  end
  walk(root, entries)
  table.sort(found)
  return found
end

--- Loads a test file and returns the case it returns.
---
--- Raises `hecate.test.LoadError` when the file does not load, raises, or returns something else.
---@param path string
---@return hecate.test.Case case
function M.load(path)
  local chunk, message = loadfile(path)
  if not chunk then error(LoadError({ message = message, context = { path = path } }), 0) end
  local ok, value = pcall(chunk)
  if not ok then
    error(LoadError({ message = ("%s raised: %s"):format(path, type(value) == "table" and value.message or value),
      cause = value, context = { path = path } }), 0)
  end
  if not case_module.is_case(value) then
    error(LoadError({ message = path .. " does not return a test case (test.Case)", context = { path = path } }), 0)
  end
  origins[value] = path
  return value
end

return M
