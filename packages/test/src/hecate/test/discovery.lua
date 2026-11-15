-- Discovery: finds `*_test.lua` files under a directory and loads the case each returns.
global <const> require, table, loadfile, pcall, type, ipairs, error

local core = require("hecate.core")
local fs = require("hecate.reactor").fs
local case_module = require("hecate.test.case")

--- Raised when a test file cannot be loaded or does not return a test case.
---@class hecate.test.LoadError : hecate.core.Error
local LoadError = core.error_class("LoadError", "hecate.test.LoadError")

---@class hecate.test.discovery
---@field LoadError hecate.test.LoadError
local M = { LoadError = LoadError }

--- Returns the paths of the files named `*_test.lua` under `directory`, recursively, sorted.
--- A missing directory yields an empty list.
---@async
---@param directory string
---@return string[] paths
function M.discover(directory)
  local found = {}
  local function walk(dir)
    local ok, entries = pcall(fs.list, dir)
    if not ok then return end
    for _, entry in ipairs(entries) do
      local path = dir .. "/" .. entry.name
      if entry.type == "directory" then walk(path)
      elseif entry.name:find("_test%.lua$") then found[#found + 1] = path end
    end
  end
  walk((directory:gsub("[/\\]+$", "")))
  table.sort(found)
  return found
end

--- Loads a test file and returns the case it returns.
---
--- Raises `hecate.test.LoadError` when the file does not load, raises, or returns something else.
---@param path string
---@return table case
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
  return value
end

return M
