-- `hecate completion <shell>` and the hidden `hecate __complete`.
global <const> table, io, require

local completion = require("hecate.cli.completion")

--- The two commands of shell completion.
---@type hecate.cli.Command[]
return {
  {
    name = "completion",
    summary = "Print the completion script of a shell (" .. table.concat(completion.shells, ", ") .. ")",
    usage = "<shell>",
    run = function(context)
      local shell = context.arguments.positionals[1]
      if not shell then
        context.print_error("hecate completion: name a shell: " .. table.concat(completion.shells, ", "))
        return 2
      end
      local script = completion.script(shell)
      if context.json then
        context.emit({ shell = shell, script = script }, script)
      else
        io.stdout:write(script)
      end
      return 0
    end,
  },
  {
    name = "__complete",
    summary = "Candidates for a partial command line (used by the completion scripts)",
    hidden = true,
    run = function(context)
      local candidates = completion.complete(context.arguments.positionals, context.commands)
      if #candidates > 0 then context.print(table.concat(candidates, "\n")) end
      return 0
    end,
  },
}
