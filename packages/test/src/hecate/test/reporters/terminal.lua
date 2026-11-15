-- Decides how a reporter talks to the terminal: colour, live redrawing and width. Nothing here
-- writes; everything that reads the environment goes through `getenv`, so tests inject their own.
global <const> type, pcall, os, package, require, math, tonumber

local reactor = require("hecate.reactor")

---@class hecate.test.terminal
local M = {}

--- Options that decide how a reporter talks to the terminal.
---@class hecate.test.TerminalOptions
---@field color? boolean  force colour on or off (default: `NO_COLOR`, `FORCE_COLOR`, then whether stdout is a terminal)
---@field live? boolean  redraw the line of the running suite in place (default: `HECATE_TEST_LIVE` `0`/`1`, else whether stdout is a terminal)
---@field width? integer  columns of the terminal (default: `COLUMNS`, else 80)
---@field is_tty? boolean|fun(): boolean  whether stdout is a terminal (default: `M.stdout_is_tty`)
---@field getenv? fun(name: string): string?  environment lookup (default: `reactor.getenv`)

local DEFAULT_WIDTH = 80

--- Whether standard output is an interactive terminal, as far as plain Lua can tell: POSIX only,
--- `TERM` set and not `dumb`, and `test -t 1` succeeds. Elsewhere (Windows, pipes, IDE consoles,
--- CI) the answer is false; pass `is_tty` or `live` to override. A `reactor` primitive would be
--- exact (luv is confined to `reactor`); proposed in OQ-138.
---@param getenv fun(name: string): string?
---@return boolean
function M.stdout_is_tty(getenv)
  if package.config:sub(1, 1) ~= "/" then return false end
  local term = getenv("TERM")
  if term == nil or term == "" or term == "dumb" then return false end
  local ok, result = pcall(os.execute, "test -t 1")
  return ok and result == true
end

--- Resolves the options of a console reporter.
---@param options? hecate.test.TerminalOptions
---@return { color: boolean, live: boolean, width: integer }
function M.resolve(options)
  options = options or {}
  local getenv = options.getenv or reactor.getenv
  local tty_known, tty_value
  local function tty()
    if not tty_known then
      local given = options.is_tty
      if type(given) == "function" then tty_value = given()
      elseif given ~= nil then tty_value = given
      else tty_value = M.stdout_is_tty(getenv) end
      tty_known = true
    end
    return tty_value
  end

  local color = options.color
  if color == nil then
    local no_color, force = getenv("NO_COLOR"), getenv("FORCE_COLOR")
    if no_color ~= nil and no_color ~= "" then color = false -- https://no-color.org
    elseif force ~= nil and force ~= "" and force ~= "0" and force ~= "false" then color = true
    else color = tty() end
  end

  local live = options.live
  if live == nil then
    -- explicit switch for consoles that run in a pty (IDEs), indistinguishable from a terminal
    local switch = getenv("HECATE_TEST_LIVE")
    if switch == "1" then live = true
    elseif switch == "0" then live = false
    else live = tty() end
  end

  local width = options.width
  if width == nil then
    local columns = math.tointeger(tonumber(getenv("COLUMNS")))
    width = columns and columns > 0 and columns or DEFAULT_WIDTH
  end
  return { color = color and true or false, live = live and true or false, width = width }
end

return M
