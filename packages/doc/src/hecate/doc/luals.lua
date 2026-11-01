-- Runs `lua-language-server --doc` and returns its JSON export (the input of the reference
-- generator). The export format is pinned to the LuaLS version of CI (`PINNED`); another
-- version is reported, not refused. The export goes to a temporary directory that is removed
-- afterwards. Platform-specific code (the shell calls) is isolated here, as in
-- system_file_system.lua; verified on Linux only until CI runs it elsewhere.
global <const> require, io, os, package, string, table, error, tostring, type, pcall

local core = require("hecate.core")
local errors = require("hecate.doc.errors")

--- Access to the LuaLS documentation export.
---@class hecate.doc.luals
local M = {}

--- The LuaLS version whose export format the generator and its fixtures are written for.
M.PINNED = "3.19.1"

local is_windows = package.config:sub(1, 1) == "\\"

--- Quotes a path as one argument of a shell command line: single quotes for a POSIX shell; double
--- quotes for `cmd.exe` on Windows, with `/` turned into `\` and the backslashes before the closing quote
--- doubled (CommandLineToArgvW). A Windows path with `"`, `%` (expanded by `cmd.exe` even inside quotes) or
--- a line break cannot be quoted safely and is refused: such names are not valid or not usable there.
---@param path string
---@param windows? boolean  quote for Windows instead of the running platform
---@return string quoted
function M.quote(path, windows)
  if windows == nil then windows = is_windows end
  if type(path) ~= "string" then error(core.ArgumentError("doc.luals.quote: expects a string"), 2) end
  if not windows then return "'" .. path:gsub("'", "'\\''") .. "'" end
  if path:find('[%c"%%]') then
    error(core.ArgumentError(("doc.luals.quote: the path %q has a character that cannot be quoted for cmd.exe"):format(path)), 2)
  end
  local native = path:gsub("/", "\\"):gsub("(\\+)$", "%1%1")
  return '"' .. native .. '"'
end

local quote = M.quote

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

--- Creates a fresh, unpredictable directory that only the current user can enter. POSIX: `mktemp -d`
--- (mode 0700, created atomically). Windows: the name of `os.tmpname`, which is unique and below the
--- per-user temporary directory; the file it creates is replaced by the directory (written by the caller).
local function temporary_directory(fs)
  if is_windows then
    local name = os.tmpname()
    os.remove(name)
    local directory = name:gsub("\\", "/") .. "-hecate-luals"
    fs:write(directory .. "/.keep", "")
    return directory
  end
  local base = (os.getenv("TMPDIR") or "/tmp"):gsub("/+$", "")
  local output, ok = capture(("mktemp -d %s 2>/dev/null"):format(quote(base .. "/hecate-luals.XXXXXXXXXX")))
  local directory = output:match("[^\r\n]+")
  if not ok or not directory then
    error(errors.BuildError({
      message = "doc.luals.export: cannot create a temporary directory below " .. base, context = { path = base },
    }), 0)
  end
  return directory
end

--- Builds the `lua-language-server` command line of an export. Pure (no I/O), so that the quoting is tested
--- for both platforms.
---@param executable string
---@param source string  directory to document
---@param directory string  output directory
---@param config? string  `.luarc.json`
---@param windows? boolean  build for Windows instead of the running platform
---@return string command
function M.command_line(executable, source, directory, config, windows)
  return ("%s --doc=%s --doc_out_path=%s --logpath=%s%s"):format(quote(executable, windows), quote(source, windows),
    quote(directory, windows), quote(directory .. "/log", windows),
    config and (" --configpath=" .. quote(config, windows)) or "")
end

--- Exports the documentation of the Lua sources below `source`. Raises
--- `hecate.doc.BuildError` if LuaLS fails or writes no export.
---@param executable string  full path of `lua-language-server`
---@param source string  directory to document (a package `src`)
---@param options { config?: string, fs: hecate.doc.FileSystem }  `config`: a `.luarc.json`
---@return string json  the content of `doc.json`
function M.export(executable, source, options)
  if type(executable) ~= "string" or type(source) ~= "string" or type(options) ~= "table" or not options.fs then
    error(core.ArgumentError("doc.luals.export: expects an executable, a source directory and { fs = ... }"), 2)
  end
  local fs = options.fs
  local directory = temporary_directory(fs)
  -- The directory is removed whatever happens (a raised error included).
  local done, output, ok, export = pcall(function()
    local text, success = capture(M.command_line(executable, source, directory, options.config) .. " 2>&1")
    return text, success, fs:read(directory .. "/doc.json")
  end)
  fs:remove_tree(directory)
  if not done then error(output, 0) end
  if not ok or not export then
    error(errors.BuildError({
      message = ("doc.luals.export: lua-language-server could not export the documentation of %s: %s"):format(source,
        (output:gsub("%s+$", ""))),
      context = { path = source },
    }), 0)
  end
  return export
end

return M
