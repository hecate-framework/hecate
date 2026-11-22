-- Shell completion: the candidates for a partial command line and the scripts that ask for them. The command
-- declarations are the only source, so completion cannot drift from the commands.
global <const> require, ipairs, table, error, tostring

local parser = require("hecate.cli.parser")

--- Completion of the `hecate` command line.
---@class hecate.cli.completion
local M = {}

local GLOBAL_FLAGS = { "--help", "--json" }

local function add_unique(list, seen, value)
  if not seen[value] then
    seen[value] = true
    list[#list + 1] = value
  end
end

--- The candidates for the last word of `words` (the words after the program name; the last one is the word being
--- typed and is empty when the cursor follows a space). Candidates are sorted and all start with that word.
---
--- First word: command names (and the global flags when it starts with `-`). Second word of a two-word command
--- such as `toolchain install`: its second words. After a command: its options and the global flags, when the
--- word starts with `-`; nothing otherwise (the shell falls back to file names).
---@param words string[]
---@param commands hecate.cli.Command[]
---@return string[] candidates
function M.complete(words, commands)
  local current = words[#words] or ""
  local previous = {}
  for index = 1, #words - 1 do previous[index] = words[index] end
  local list, seen = {}, {}

  -- Words before the current one that are not flags form the (possibly partial) command name.
  local names = {}
  for _, word in ipairs(previous) do
    if word:sub(1, 1) ~= "-" then names[#names + 1] = word end
  end
  local command = parser.find_command(names, commands)

  if command then
    if current:sub(1, 1) == "-" then
      for _, spec in ipairs(command.options or {}) do add_unique(list, seen, "--" .. spec.name) end
      for _, flag in ipairs(GLOBAL_FLAGS) do add_unique(list, seen, flag) end
    end
  elseif #names == 0 then
    if current:sub(1, 1) == "-" then
      for _, flag in ipairs(GLOBAL_FLAGS) do add_unique(list, seen, flag) end
    else
      for _, candidate in ipairs(commands) do
        if not candidate.hidden then add_unique(list, seen, (candidate.name:match("^(%S+)"))) end
      end
    end
  elseif #names == 1 and current:sub(1, 1) ~= "-" then
    for _, candidate in ipairs(commands) do
      local first, second = candidate.name:match("^(%S+)%s+(%S+)$")
      if first == names[1] and not candidate.hidden then add_unique(list, seen, second) end
    end
  end

  local result = {}
  for _, candidate in ipairs(list) do
    if candidate:sub(1, #current) == current then result[#result + 1] = candidate end
  end
  table.sort(result)
  return result
end

--- The shells `script` knows.
---@type string[]
M.shells = { "bash", "zsh", "fish", "powershell" }

local SCRIPTS = {
  bash = [[
# hecate completion for bash: source it, or save it as ~/.local/share/bash-completion/completions/hecate
_hecate_complete() {
  local IFS=$'\n'
  COMPREPLY=( $(hecate __complete -- "${COMP_WORDS[@]:1:$COMP_CWORD}") )
}
complete -o default -F _hecate_complete hecate
]],
  zsh = [[
#compdef hecate
# hecate completion for zsh: save it as _hecate in a directory of $fpath, then run compinit
_hecate() {
  local -a candidates
  candidates=("${(@f)$(hecate __complete -- "${(@)words[2,CURRENT]}")}")
  compadd -a candidates
}
compdef _hecate hecate
]],
  fish = [[
# hecate completion for fish: save it as ~/.config/fish/completions/hecate.fish
complete -c hecate -f -a '(hecate __complete -- (commandline -opc)[2..-1] (commandline -ct))'
]],
  powershell = [[
# hecate completion for PowerShell: add this to your $PROFILE
Register-ArgumentCompleter -Native -CommandName hecate -ScriptBlock {
  param($wordToComplete, $commandAst, $cursorPosition)
  $words = @($commandAst.CommandElements | Select-Object -Skip 1 | ForEach-Object { $_.ToString() })
  if ($wordToComplete -eq '') { $words += '""' }
  hecate __complete -- @words | ForEach-Object {
    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
  }
}
]],
}

--- The completion script of `shell`: one of `shells`. Raises an error naming the supported shells otherwise.
---@param shell string
---@return string script
function M.script(shell)
  local script = SCRIPTS[shell]
  if not script then
    error("unknown shell '" .. tostring(shell) .. "' (expected " .. table.concat(M.shells, ", ") .. ")", 0)
  end
  return script
end

return M
