-- Runs `lua-language-server --doc` and returns its JSON export (the input of the reference
-- generator). The export format is pinned to the LuaLS version of CI (`PINNED`); another
-- version is reported, not refused. The export goes to a temporary directory that is removed
-- afterwards. Platform-specific code (the shell calls) is isolated here, as in
-- system_filesystem.lua; verified on Linux only until CI runs it elsewhere.
global <const> require, io, os, package, math, string, table, error, tostring, type

local core = require("hecate.core")
local errors = require("hecate.doc.errors")

local M = {}

--- The LuaLS version whose export format the generator and its fixtures are written for.
M.PINNED = "3.19.1"

local is_windows = package.config:sub(1, 1) == "\\"

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

--- Finds `lua-language-server` on the path. Returns its full path, or nil.
---@return string? executable
function M.locate()
  local output, ok = capture(is_windows and "where lua-language-server 2>nul"
    or "command -v lua-language-server 2>/dev/null")
  if not ok then return nil end
  return output:match("[^\r\n]+")
end

--- Returns the version `executable` reports ("3.19.1"), or nil.
---@param executable string
---@return string? version
function M.version(executable)
  local output = capture(("%s --version 2>%s"):format(quote(executable), is_windows and "nul" or "/dev/null"))
  return output:match("(%d+%.%d+%.%d+)")
end

local function temporary_directory()
  local base = (os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP") or "/tmp"):gsub("\\", "/"):gsub("/+$", "")
  math.randomseed(os.time() + math.floor(os.clock() * 1e6))
  return ("%s/hecate-luals-%d"):format(base, math.random(1, 1e9))
end

--- Exports the documentation of the Lua sources below `source`. Raises
--- `hecate.doc.BuildError` if LuaLS fails or writes no export.
---@param executable string  full path of `lua-language-server`
---@param source string  directory to document (a package `src`)
---@param options { config?: string, fs: hecate.doc.FileSystem }  `config`: a `.luarc.json`
---@return string json  the content of `doc.json`
function M.export(executable, source, options)
  if type(executable) ~= "string" or type(source) ~= "string" or type(options) ~= "table" or not options.fs then
    error(core.ArgumentError("luals.export expects an executable, a source directory and { fs = ... }"), 2)
  end
  local fs = options.fs
  local directory = temporary_directory()
  fs:write(directory .. "/.keep", "")
  local command = ("%s --doc=%s --doc_out_path=%s --logpath=%s%s"):format(quote(executable), quote(source),
    quote(directory), quote(directory .. "/log"),
    options.config and (" --configpath=" .. quote(options.config)) or "")
  local output, ok = capture(command .. " 2>&1")
  local export = fs:read(directory .. "/doc.json")
  fs:remove_tree(directory)
  if not ok or not export then
    error(errors.BuildError({
      message = ("lua-language-server could not export the documentation of %s: %s"):format(source,
        output:gsub("%s+$", "")),
      context = { path = source },
    }), 0)
  end
  return export
end

return M
