local test = require("harness.test")
local T = test.Case("CliCompletionShellsTest")

-- The completion scripts are run by the real shells, where the shell exists (a shell that is not installed skips its
-- test). A `hecate` shim on the PATH runs the entry point of this checkout.
local is_windows = package.config:sub(1, 1) == "\\"
local here = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/tests/unit/[^/]+$") or "packages/cli"
local entry = (io.popen(is_windows and "cd" or "pwd"):read("l") or ".") .. "/" .. here .. "/bin/hecate.lua"
if is_windows then entry = entry:gsub("\\", "/") end

local function exists(program)
  local probe = is_windows and ("where " .. program .. " >NUL 2>&1") or ("command -v " .. program .. " >/dev/null 2>&1")
  local ok = os.execute(probe)
  return ok == true
end

local function temporary_directory()
  local name = os.tmpname()
  os.remove(name)
  os.execute((is_windows and "mkdir " or "mkdir -p ") .. '"' .. name .. '"')
  return name
end

local function write(path, text)
  local file = assert(io.open(path, "wb"))
  file:write(text)
  file:close()
end

--- Creates the `hecate` shim and returns the directory to put on the PATH.
local function shim()
  local directory = temporary_directory()
  if is_windows then
    write(directory .. "/hecate.cmd", '@echo off\r\nlua "' .. entry .. '" %*\r\n')
  else
    write(directory .. "/hecate", '#!/bin/sh\nexec lua "' .. entry .. '" "$@"\n')
    os.execute('chmod +x "' .. directory .. '/hecate"')
  end
  return directory
end

--- The lines a shell prints for the command line `typed` after loading the script.
local function lines(output)
  local list = {}
  for line in (output or ""):gmatch("[^\r\n]+") do list[#list + 1] = line end
  return list
end

local function run(directory, command)
  local separator = is_windows and ";" or ":"
  local prefix = is_windows and ('set "PATH=' .. directory .. separator .. '%PATH%" && ') or ('PATH="' .. directory .. separator .. '$PATH" ')
  local handle = io.popen(prefix .. command .. " 2>&1")
  local output = handle and handle:read("a") or ""
  if handle then handle:close() end
  return lines(output)
end

local function contains(list, value)
  for _, entry in ipairs(list) do
    if entry == value then return true end
  end
  return false
end

function T:test_fish_completes_commands_and_options()
  if is_windows or not exists("fish") then return end
  local directory = shim()
  local function complete(typed)
    return run(directory, "fish -c \"hecate completion fish | source; complete -C '" .. typed .. "'\"")
  end
  self:assert_true(contains(complete("hecate comp"), "completion"))
  local all = complete("hecate ")
  self:assert_true(contains(all, "version") and contains(all, "completion"))
  self:assert_false(contains(all, "__complete"))
  self:assert_true(contains(complete("hecate completion --"), "--json"))
end

function T:test_zsh_function_offers_the_candidates_to_compadd()
  if is_windows or not exists("zsh") then return end
  local directory = shim()
  local script = temporary_directory() .. "/probe.zsh"
  -- compdef and compadd are stubbed: compinit is not available in a non-interactive shell; the function under test
  -- is the one the script defines, which builds the candidates from `hecate __complete`.
  write(script, [[
compdef() { :; }
compadd() { shift; print -r -- "${(@P)1}"; }
eval "$(hecate completion zsh)"
words=(hecate comp); CURRENT=2; _hecate; print -- "--"
words=(hecate ''); CURRENT=2; _hecate; print -- "--"
words=(hecate completion --); CURRENT=3; _hecate
]])
  local output = table.concat(run(directory, 'zsh -f "' .. script .. '"'), "\n")
  -- Three queries separated by `--`: a prefix, an empty word, an option. The set of commands grows with the CLI, so the
  -- assertions name members and not the whole list.
  local first, second, third = output:match("^(.-)\n%-%-\n(.-)\n%-%-\n(.*)$")
  self:assert_true(first == "completion", output)
  self:assert_true((" " .. second .. " "):find(" completion ", 1, true) ~= nil and (" " .. second .. " "):find(" version ", 1, true) ~= nil, output)
  self:assert_true(second:find("__complete", 1, true) == nil, output)
  self:assert_true(third:find("%-%-help") ~= nil and third:find("%-%-json") ~= nil, output)
end

function T:test_powershell_completes_commands()
  if not exists("pwsh") then return end
  local directory = shim()
  local script = temporary_directory() .. "/probe.ps1"
  write(script, [[
# Standard: the shim of Windows is a .cmd file, for which the default mode of 7.3+ is still the legacy one.
if ($PSVersionTable.PSVersion.Major -ge 7 -and $PSVersionTable.PSVersion.Minor -ge 3 -or $PSVersionTable.PSVersion.Major -gt 7) { $PSNativeCommandArgumentPassing = 'Standard' }
. ([scriptblock]::Create((hecate completion powershell | Out-String)))
(TabExpansion2 'hecate comp' 11).CompletionMatches | ForEach-Object { $_.CompletionText }
'--'
(TabExpansion2 'hecate ' 7).CompletionMatches | ForEach-Object { $_.CompletionText }
]])
  local output = table.concat(run(directory, 'pwsh -NoProfile -File "' .. script .. '"'), "\n")
  self:assert_true(output:find("completion", 1, true) ~= nil, output)
  self:assert_true(output:find("version", 1, true) ~= nil, output)
  self:assert_true(output:find("__complete", 1, true) == nil, output)
  -- After `--` the second query (an empty last word) lists commands, not the files of the directory.
  local after = output:match("%-%-\n(.*)$") or ""
  self:assert_true(after:find("version", 1, true) ~= nil and after:find("%.editorconfig") == nil, output)
end

return T
