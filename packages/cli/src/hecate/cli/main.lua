-- The entry of the `hecate` command, shared by the script of a checkout (`bin/hecate.lua`), an installed rock and the
-- self-contained executable (OQ-13, ADR 0029): it finds out what the process runs on (Lua release, LuaRocks, libuv,
-- platform, current directory, the interpreter for the project) and runs the command line.
global <const> arg, io, os, package, require, pcall, type, ipairs, table, _VERSION

---@class hecate.cli.MainOverrides
---@field hecate_version? string
---@field lua_interpreter? string  the interpreter for the processes of the project (default: `arg[-1]`, the one that runs this script)
---@field lua_interpreter_arguments? string[]  the arguments that put it in interpreter mode (the executable: `--lua`)
---@field lua_release? string  the exact release of the Lua that runs this process (`5.5.1`); the executable knows it, a plain `lua` is asked with `-v`
---@field luarocks_program? string  the program that runs LuaRocks (default: `luarocks` on the path; the executable: itself)
---@field luarocks_arguments? string[]  the arguments that make it run LuaRocks (the executable: `--luarocks`)

--- Building the runtime of the process and running a command line.
---@class hecate.cli.main
local M = {}

local windows = package.config:sub(1, 1) == "\\"

--- Quotes a word of a command line for the shell that `io.popen` uses: POSIX single quotes (nothing inside is expanded),
--- or on Windows double quotes with `"` doubled. `cmd.exe` still expands `%name%` inside the quotes and cannot be told not
--- to; a path with `%` is therefore not supported there.
---@param value string
---@param for_windows? boolean  default: the running platform
---@return string quoted
function M.quote(value, for_windows)
  if for_windows == nil then for_windows = windows end
  if for_windows then return '"' .. value:gsub('"', '""') .. '"' end
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

--- The command line of a program and its words, ready for `io.popen`. `cmd.exe /c` drops the first and last quote of a
--- line that starts with one, so on Windows such a line is wrapped in one more pair.
---@param words string[]  already quoted where needed
---@param for_windows? boolean  default: the running platform
---@return string command
function M.command_line(words, for_windows)
  if for_windows == nil then for_windows = windows end
  local line = table.concat(words, " ")
  if for_windows and line:find('^"') then return '"' .. line .. '"' end
  return line
end

--- The platform as `<os>-<architecture>`, from the path separator, the environment and `uname`.
---@return string platform
function M.platform()
  if windows then
    local architecture = (os.getenv("PROCESSOR_ARCHITECTURE") or "x86_64"):lower()
    return "windows-" .. (architecture == "amd64" and "x86_64" or architecture)
  end
  local handle = io.popen("uname -sm 2>/dev/null")
  local line = handle and handle:read("l") or nil
  if handle then handle:close() end
  local system, machine = (line or ""):match("^(%S+)%s+(%S+)")
  if not system then return "unknown" end
  return system:lower() .. "-" .. (machine == "arm64" and "aarch64" or machine)
end

--- The version of LuaRocks (`luarocks --version`), nil when there is none.
---@param program? string  default `luarocks` (found on the path)
---@param leading? string[]  arguments before `--version` (the executable: `--luarocks`)
---@return string? version
function M.luarocks_version(program, leading)
  local words = { program and M.quote(program) or "luarocks" }
  for _, value in ipairs(leading or {}) do words[#words + 1] = M.quote(value) end
  words[#words + 1] = "--version"
  words[#words + 1] = "2>" .. (windows and "nul" or "/dev/null")
  local handle = io.popen(M.command_line(words))
  local line = handle and handle:read("l") or nil
  if handle then handle:close() end
  return line and line:match("(%d+%.%d+%.%d+)") or nil
end

--- The absolute path of the current directory with forward slashes. On Windows libuv is asked (`uv_cwd`, UTF-8: the
--- application manifest makes the process use UTF-8 paths); `cd` answers in the OEM code page and would corrupt a
--- directory with non-ASCII characters, so it stays only the fallback. Elsewhere `pwd`.
---@return string? directory
function M.current_directory()
  if windows then
    local loaded, luv = pcall(require, "luv")
    if loaded and type(luv.cwd) == "function" then
      local directory = luv.cwd()
      if type(directory) == "string" and directory ~= "" then return (directory:gsub("\\", "/")) end
    end
  end
  local handle = io.popen(windows and "cd" or "pwd")
  local line = handle and handle:read("l") or nil
  if handle then handle:close() end
  return line and (line:gsub("\\", "/")) or nil
end

--- The exact version of the Lua that runs the process (`5.5.1`): the interpreter prints it with `-v` (after its own
--- leading arguments); `_VERSION` only has the line (`5.5`), which is the fallback when the interpreter cannot be asked.
---@param interpreter? string
---@param leading? string[]
---@return string release
function M.lua_release(interpreter, leading)
  local line = _VERSION:match("%d+%.%d+") or _VERSION
  if interpreter then
    local words = { M.quote(interpreter) }
    for _, value in ipairs(leading or {}) do words[#words + 1] = M.quote(value) end
    words[#words + 1] = "-v"
    words[#words + 1] = "2>&1"
    local handle = io.popen(M.command_line(words))
    local output = handle and handle:read("l") or nil
    if handle then handle:close() end
    local release = output and output:match("^Lua (%d+%.%d+%.%d+)")
    if release and release:sub(1, #line) == line then return release end
  end
  return line
end

--- The version of Hecate that the executable was built from: the generated module `hecate.cli.version` (`build-cli` writes it from
--- the file `VERSION`), `0.0.0` when the CLI runs from the sources.
---@return string version
function M.embedded_version()
  local ok, version = pcall(require, "hecate.cli.version")
  if ok and type(version) == "string" then return version end
  return "0.0.0"
end

--- The runtime of this process, for `hecate.cli.run`.
---@param overrides? hecate.cli.MainOverrides
---@return hecate.cli.Runtime runtime
function M.runtime(overrides)
  overrides = overrides or {}
  local interpreter = overrides.lua_interpreter or arg[-1]
  local libuv_ok, luv = pcall(require, "luv")
  return {
    hecate_version = overrides.hecate_version or M.embedded_version(),
    lua_version = overrides.lua_release or M.lua_release(interpreter, overrides.lua_interpreter_arguments),
    libuv_version = libuv_ok and luv.version_string and luv.version_string() or nil,
    luarocks_version = M.luarocks_version(overrides.luarocks_program, overrides.luarocks_arguments),
    luarocks_program = overrides.luarocks_program,
    luarocks_arguments = overrides.luarocks_arguments,
    platform = M.platform(),
    project_dir = M.current_directory(),
    lua_interpreter = interpreter,
    lua_interpreter_arguments = overrides.lua_interpreter_arguments,
  }
end

--- Runs a command line and returns the exit code.
---@param arguments string[]  the arguments after the program name (`arg`)
---@param overrides? hecate.cli.MainOverrides
---@return integer exit_code
function M.run(arguments, overrides)
  local cli = require("hecate.cli")
  return cli.run(arguments, { commands = cli.commands, runtime = M.runtime(overrides) })
end

return M
