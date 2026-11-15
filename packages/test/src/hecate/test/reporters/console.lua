-- Console reporter: one line per suite with a loading bar of its tests, the details of every
-- failure and error at the end, a summary line. Output for people, in two modes:
--   * live (a terminal): the line of the running suite is redrawn in place as tests finish;
--   * plain (pipes, CI, IDE consoles): each suite line is written once, completed, with no cursor control.
-- Colour is separate from the mode. All escape sequences come from `reporters.ansi`.
global <const> require, io, ipairs, math, table, tostring

local core = require("hecate.core")
local ansi = require("hecate.test.reporters.ansi")
local terminal = require("hecate.test.reporters.terminal")

--- Options of a console reporter (those of `hecate.test.TerminalOptions` too).
---@class hecate.test.ConsoleOptions : hecate.test.TerminalOptions
---@field write? fun(text: string)  receives the output, default `io.stdout:write` then flush
---@field bar_width? integer  most cells of a loading bar (default 40)

--- Writes the events of a run for a person.
---@class hecate.test.ConsoleReporter : hecate.test.Reporter
---@overload fun(options?: hecate.test.ConsoleOptions): hecate.test.ConsoleReporter
local ConsoleReporter = core.class("ConsoleReporter")

local DEFAULT_BAR_WIDTH = 40
local TAB_COLUMNS = 8 -- a tab counts as the next multiple of 8 columns; the line starts with a 4-letter word
local MIN_NAME, MIN_CELLS = 10, 10

local STATUS_WORD = { passed = "PASS", failed = "FAIL", errored = "ERROR" }
local STATUS_COLOR = { passed = "green", failed = "red", errored = "red" }

--- Creates a console reporter.
---@param options? hecate.test.ConsoleOptions
function ConsoleReporter:init(options)
  options = options or {}
  self._write = options.write or function(text)
    io.stdout:write(text)
    io.stdout:flush()
  end
  local resolved = terminal.resolve(options)
  self._color, self._live, self._width = resolved.color, resolved.live, resolved.width
  self._bar_width = options.bar_width or DEFAULT_BAR_WIDTH
  self._problems = {}
  self._suite = nil
end

local function plural(count, word) return ("%d %s%s"):format(count, word, count == 1 and "" or "s") end

local function digits(number) return #tostring(number) end

-- Keeps the end of a name that does not fit: the tail of a path is what tells files apart.
local function fit(name, room)
  if #name <= room then return name end
  return "..." .. name:sub(#name - room + 4)
end

-- Lays out the line of a suite whose statistics read `stats`: the name (shortened when it must be)
-- and the number of cells of the loading bar, so that the line stays within the width.
local function layout(self, stats)
  local suite = self._suite
  local rest = TAB_COLUMNS + 1 + #stats + 3 -- tab, space, statistics, " [" and "]"
  local name = fit(suite.name, math.max(MIN_NAME, self._width - rest - math.min(suite.total, MIN_CELLS)))
  local cells = math.max(1, math.min(suite.total, self._bar_width, self._width - rest - #name))
  return name, cells
end

-- The statistics a live line reserves room for: three digits of assertions (a line that outgrows
-- them is a column or two longer), as many digits of failures and errors as there are tests.
local function reserved_stats(self)
  local nines = ("9"):rep(digits(self._suite.total))
  return ("(999 assertions, %s failed, %s errored)"):format(nines, nines)
end

-- The cell that stands for test `index` (1-based): proportional when there are more tests than cells.
local function cell_of(index, total, cells)
  if total <= cells then return index end
  return (index - 1) * cells // total + 1
end

-- Draws the bar: a cell is red when a test it stands for failed or errored, green when every test
-- it stands for passed, blank while some has not finished.
local function draw_bar(self, cells)
  local suite = self._suite
  local size, finished, failed = {}, {}, {}
  for cell = 1, cells do size[cell], finished[cell], failed[cell] = 0, 0, 0 end
  for index = 1, suite.total do
    local cell = cell_of(index, suite.total, cells)
    size[cell] = size[cell] + 1
    local status = suite.statuses[index]
    if status then finished[cell] = finished[cell] + 1 end
    if status and status ~= "passed" then failed[cell] = failed[cell] + 1 end
  end
  local parts = {}
  for cell = 1, cells do
    if failed[cell] > 0 then
      -- without colour a red cell would look like a green one: it is an "F"
      parts[cell] = self._color and ansi.paint(".", "red", true) or "F"
    elseif finished[cell] == size[cell] then
      parts[cell] = ansi.paint(".", "green", self._color)
    else
      parts[cell] = " "
    end
  end
  return table.concat(parts)
end

-- The line of the running suite: orange TEST word, "in progress", the bar so far.
local function progress_line(self)
  local name, cells = layout(self, reserved_stats(self))
  return ("%s\t%s (in progress...) [%s]"):format(ansi.paint("TEST", "orange", self._color), name, draw_bar(self, cells))
end

-- The line of a finished suite. A live line keeps the size of the bar it had while in progress.
local function final_line(self, summary)
  local status = (summary.failed + summary.errored) == 0 and "passed" or "failed"
  local stats = ("(%s, %d failed, %d errored)"):format(
    plural(summary.assertions, "assertion"), summary.failed, summary.errored)
  local name, cells = layout(self, self._live and reserved_stats(self) or stats)
  return ("%s\t%s %s [%s]"):format(
    ansi.paint(STATUS_WORD[status], STATUS_COLOR[status], self._color), name, stats, draw_bar(self, cells))
end

--- Handles one event of the run.
---@param event hecate.test.Event
function ConsoleReporter:handle(event)
  local kind = event.type
  if kind == "run_started" then
    self._write(("Running %d test(s)\n"):format(event.total))
  elseif kind == "suite_started" then
    self._suite = { name = event.suite, total = event.total, statuses = {} }
    if self._live then self._write(progress_line(self)) end
  elseif kind == "test_finished" then
    local result = event.result --[[@as hecate.test.Result]]
    self._suite.statuses[event.index] = result.status
    if result.status ~= "passed" then self._problems[#self._problems + 1] = result end
    if self._live then self._write(ansi.REDRAW .. progress_line(self)) end
  elseif kind == "suite_finished" then
    local line = final_line(self, event.summary) .. "\n"
    self._write(self._live and (ansi.REDRAW .. line) or line)
    self._suite = nil
  elseif kind == "run_finished" then
    self:_finish(event.summary --[[@as hecate.test.Summary]])
  end
end

-- The details of every failure and error, then the totals.
function ConsoleReporter:_finish(summary)
  for _, result in ipairs(self._problems) do
    local word = ansi.paint(STATUS_WORD[result.status], STATUS_COLOR[result.status], self._color)
    self._write(("\n%s %s\n"):format(word, result.name))
    if result.location then self._write("  at " .. result.location .. "\n") end
    if result.message then self._write("  " .. result.message:gsub("\n", "\n  ") .. "\n") end
    local trace = result.traceback and result.traceback:match("stack traceback:.*") -- its first line repeats the message
    if trace then self._write("  " .. trace:gsub("\n", "\n  ") .. "\n") end
  end
  self._write(("\n%s in %s, %s: %d passed, %d failed, %d errored\n"):format(
    plural(summary.total, "test"), plural(#summary.suites, "suite"), plural(summary.assertions, "assertion"),
    summary.passed, summary.failed, summary.errored))
end

return core.finalise(ConsoleReporter)
