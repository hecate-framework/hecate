-- Line coverage: the lines of the sources that ran, recorded by a debug line hook in the main thread and in every
-- coroutine created while it is on, and reported as LCOV (testing.md, "Coverage"). It replaces the recorder of the
-- bootstrap harness (`tools/harness/run_file.lua`) and keeps its rules: a line counts when it holds code (an
-- approximation: blank lines, comments and lines made only of block delimiters do not), and the region between the
-- comments `-- coverage: off` and `-- coverage: on` is not counted (code that runs in another Lua state, which no hook
-- sees; the comment says why).
global <const> require, type, error, pairs, ipairs, pcall, io, string, table, tonumber, tostring, coroutine, debug, math

local core = require("hecate.core")

--- Records which lines of the selected sources run. Make one, `start` it, run the code, `stop` it, then read the
--- result. A recorder can be started again, and `merge` adds the hits of another run (a worker process).
---@class hecate.test.LineCoverage
---@overload fun(options?: hecate.test.LineCoverageOptions): hecate.test.LineCoverage
local LineCoverage = core.class("LineCoverage")

--- Options of a line coverage.
---@class hecate.test.LineCoverageOptions
---@field include? string|fun(path: string): boolean  sources to record: a Lua pattern matched against the path (with `/` separators), or a predicate; default `"/src/"`
---@field exclude? string  a Lua pattern: sources that match are not recorded, whatever `include` says

local STRUCTURAL = { ["end"] = true, ["else"] = true, ["do"] = true, ["then"] = true, ["repeat"] = true,
  ["}"] = true, ["{"] = true, [")"] = true, ["},"] = true, ["end)"] = true, ["end,"] = true, ["})"] = true }

-- Lines of a Lua source that hold code. Each line is read for its code: comments (line and long, of any level),
-- the inside of strings (short, and long of any level, across lines) and a shebang are not code; a line that is
-- only a block delimiter (`end`, `}`, `)`) is not counted either, since no instruction belongs to it. The region
-- between the comments `-- coverage: off` and `-- coverage: on` is left out.
local function executable_lines(source)
  local lines, off, long, number = {}, false, nil, 0
  for line in (source .. "\n"):gmatch("(.-)\r?\n") do
    number = number + 1
    local trimmed = line:match("^%s*(.-)%s*$")
    local marker
    if not long then
      if trimmed:find("^%-%-%s*coverage:%s*off") then marker = "off"
      elseif trimmed:find("^%-%-%s*coverage:%s*on") then marker = "on" end
    end
    local code, position = {}, 1
    if number == 1 and line:sub(1, 1) == "#" then position = #line + 1 end
    while position <= #line do
      if long then
        local first, last = line:find("]" .. ("="):rep(long.level) .. "]", position, true)
        if first then
          position, long = last + 1, nil
        else
          position = #line + 1
        end
      elseif line:find("^%-%-%[=*%[", position) then
        local level = #line:match("^%-%-%[(=*)%[", position)
        long, position = { level = level }, position + 4 + level
      elseif line:sub(position, position + 1) == "--" then
        position = #line + 1
      elseif line:find("^%[=*%[", position) then
        local level = #line:match("^%[(=*)%[", position)
        code[#code + 1] = "[["
        long, position = { level = level }, position + 2 + level
      else
        local c = line:sub(position, position)
        if c == '"' or c == "'" then
          local close = position + 1
          while close <= #line and line:sub(close, close) ~= c do
            close = close + (line:sub(close, close) == "\\" and 2 or 1)
          end
          code[#code + 1] = "s"
          position = close + 1
        else
          code[#code + 1] = c
          position = position + 1
        end
      end
    end
    local text = table.concat(code):match("^%s*(.-)%s*$")
    if marker == "off" then
      off = true
    elseif marker == "on" then
      off = false
    elseif not off and text ~= "" and not STRUCTURAL[text] then
      lines[number] = true
    end
  end
  return lines
end

-- A path with `/` separators, the `.` and `..` segments resolved, repeated separators merged, and the drive letter of
-- a Windows path in lower case (`C:` and `c:` name one file). A leading `/` or `//` (a UNC path) is kept.
local function normalise(path)
  path = path:gsub("\\", "/")
  local root = path:match("^//") and "//" or path:match("^/") and "/" or ""
  local out = {}
  for segment in path:gmatch("[^/]+") do
    if segment == "." then
      -- stays where it is
    elseif segment == ".." then
      if #out > 0 and out[#out] ~= ".." then
        out[#out] = nil
      elseif root == "" then
        out[#out + 1] = ".."
      end
    else
      out[#out + 1] = segment
    end
  end
  local joined = root .. table.concat(out, "/")
  joined = joined:gsub("^(%a):", function(letter) return letter:lower() .. ":" end)
  return joined == "" and (root ~= "" and root or ".") or joined
end

--- Creates a recorder.
---
--- Raises `hecate.core.ArgumentError` for options that are not a table of the known fields.
---@param options? hecate.test.LineCoverageOptions
function LineCoverage:init(options)
  if options ~= nil and type(options) ~= "table" then
    error(core.ArgumentError("test.LineCoverage: options must be a table"), 3)
  end
  options = options or {}
  for key in pairs(options) do
    if key ~= "include" and key ~= "exclude" then
      error(core.ArgumentError("test.LineCoverage: unknown option " .. tostring(key)), 3)
    end
  end
  local include, exclude = options.include or "/src/", options.exclude
  if type(include) ~= "string" and type(include) ~= "function" then
    error(core.ArgumentError("test.LineCoverage: include must be a pattern or a predicate"), 3)
  end
  if exclude ~= nil and type(exclude) ~= "string" then
    error(core.ArgumentError("test.LineCoverage: exclude must be a pattern"), 3)
  end
  self._include, self._exclude = include, exclude
  self._hits = {}
  self._decided = {}
  self._running = false
end

-- The recorded path of a chunk source ("@file"), or false when it is not recorded.
local function decide(self, source)
  local known = self._decided[source]
  if known ~= nil then return known end
  ---@type string|false
  local path = false
  if source:sub(1, 1) == "@" then
    local candidate = normalise(source:sub(2))
    local selected
    if type(self._include) == "function" then selected = self._include(candidate)
    else selected = candidate:find(self._include) ~= nil end
    if selected and not (self._exclude and candidate:find(self._exclude)) then path = candidate end
  end
  self._decided[source] = path
  return path
end

--- Starts recording: a line hook on the running thread, and on every coroutine created from now on. Returns the
--- recorder, so that `local recording <close> = coverage:start()` stops it when the block ends, also on an error.
---
--- Raises `hecate.core.StateError` when it is already recording.
---@return hecate.test.LineCoverage self
function LineCoverage:start()
  if self._running then error(core.StateError("test.LineCoverage: already recording"), 2) end
  self._running = true
  local hits = self._hits
  local previous_hook, previous_mask, previous_count = debug.gethook()
  local function record(event, line)
    -- a coroutine started while recording keeps its hook after `stop`: it must record nothing then
    if not self._running then return end
    if event ~= "line" then
      if previous_hook then previous_hook(event, line) end
      return
    end
    local path = decide(self, debug.getinfo(2, "S").source)
    if path then
      local set = hits[path]
      if not set then set = {}; hits[path] = set end
      set[line] = (set[line] or 0) + 1
    end
  end
  local create, wrap = coroutine.create, coroutine.wrap
  self._restore = function()
    coroutine.create, coroutine.wrap = create, wrap
    debug.sethook(previous_hook, previous_mask, previous_count)
  end
  debug.sethook(record, "l")
  ---@diagnostic disable-next-line: duplicate-set-field
  coroutine.create = function(f)
    local co = create(f)
    debug.sethook(co, record, "l")
    return co
  end
  ---@diagnostic disable-next-line: duplicate-set-field
  coroutine.wrap = function(f)
    return wrap(function(...)
      debug.sethook(record, "l")
      return f(...)
    end)
  end
  return self
end

--- Stops recording and restores the hook and the coroutine functions it replaced.
---
--- Raises `hecate.core.StateError` when it is not recording.
function LineCoverage:stop()
  if not self._running then error(core.StateError("test.LineCoverage: not recording"), 2) end
  self._running = false
  self._restore()
  self._restore = nil
end

--- Stops the recording when the recorder is closed while it is still recording (`local recording <close> = coverage:start()`).
---@private
function LineCoverage:__close()
  if self._running then self:stop() end
end

--- The hits recorded so far: `{ [path] = { [line] = count } }`. The table is the recorder's own: do not change it.
---@return table<string, table<integer, integer>> hits
function LineCoverage:hits() return self._hits end

--- Adds the hits of another run, in the form of `hits()`. The keys of the lines may be numbers or their text (JSON
--- turns them into text); every count is a non-negative integer. Nothing is added when the table is malformed.
---
--- Raises `hecate.core.ArgumentError` for a table of another shape.
---@param hits table<string, table<integer|string, integer>>
function LineCoverage:merge(hits)
  local function malformed() error(core.ArgumentError("test.LineCoverage: merge expects { [path] = { [line] = count } }"), 3) end
  if type(hits) ~= "table" then malformed() end
  local checked = {}
  for path, lines in pairs(hits) do
    if type(path) ~= "string" or type(lines) ~= "table" then malformed() end
    for line, count in pairs(lines) do
      local number = tonumber(line)
      if number == nil or math.type(number) ~= "integer" or number < 1 or math.type(count) ~= "integer" or count < 0 then
        malformed()
      end
      checked[#checked + 1] = { path, number, count }
    end
  end
  for _, entry in ipairs(checked) do
    local set = self._hits[entry[1]]
    if not set then set = {}; self._hits[entry[1]] = set end
    set[entry[2]] = (set[entry[2]] or 0) + entry[3]
  end
end

--- The settings a worker process needs to record the same sources: `{ include, exclude }`.
---
--- Raises `hecate.core.ArgumentError` when `include` is a predicate, which cannot be sent to another process.
---@return { include: string, exclude: string? } settings
function LineCoverage:settings()
  if type(self._include) ~= "string" then
    error(core.ArgumentError("test.LineCoverage: a recorder with a predicate cannot be used by worker processes; give a pattern"), 2)
  end
  return { include = self._include, exclude = self._exclude }
end

--- Per-file figures, sorted by path.
---@class hecate.test.CoverageFile
---@field path string
---@field total integer  lines that hold code
---@field covered integer  of those, the lines that ran
---@field percent number  0 to 100 (100 for a file without code)
---@field lines table<integer, integer>  line to hits, for every line that holds code

--- The whole report.
---@class hecate.test.CoverageReport
---@field files hecate.test.CoverageFile[]  the recorded sources that could be read
---@field total integer
---@field covered integer
---@field percent number

local function read(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local text = file:read("a")
  file:close()
  return text
end

--- The figures of every recorded source that can be read. Only lines that hold code count: a hit on any other line
--- is ignored. Sources with no line run are not known and so are not listed.
---@return hecate.test.CoverageReport report
function LineCoverage:report()
  local files, total, covered = {}, 0, 0
  local paths = {}
  for path in pairs(self._hits) do paths[#paths + 1] = path end
  table.sort(paths)
  for _, path in ipairs(paths) do
    local text = read(path)
    if text then
      local lines, count, ran = {}, 0, 0
      for line in pairs(executable_lines(text)) do
        local hits = self._hits[path][line] or 0
        lines[line] = hits
        count = count + 1
        if hits > 0 then ran = ran + 1 end
      end
      files[#files + 1] = { path = path, total = count, covered = ran,
        percent = count == 0 and 100 or ran * 100 / count, lines = lines }
      total, covered = total + count, covered + ran
    end
  end
  return { files = files, total = total, covered = covered, percent = total == 0 and 100 or covered * 100 / total }
end

--- The coverage of the files whose path matches the Lua pattern `pattern`, as a percentage, or nil when none matches.
---@param pattern string
---@return number? percent
function LineCoverage:percent(pattern)
  local total, covered = 0, 0
  for _, file in ipairs(self:report().files) do
    if file.path:find(pattern) then total, covered = total + file.total, covered + file.covered end
  end
  if total == 0 then return nil end
  return covered * 100 / total
end

--- The report as LCOV (`SF`, `DA`, `LF`, `LH`, `end_of_record`), the format `genhtml` and most services read.
---@return string text
function LineCoverage:lcov()
  local out = {}
  for _, file in ipairs(self:report().files) do
    out[#out + 1] = "SF:" .. file.path
    local numbers = {}
    for line in pairs(file.lines) do numbers[#numbers + 1] = line end
    table.sort(numbers)
    for _, line in ipairs(numbers) do out[#out + 1] = ("DA:%d,%d"):format(line, file.lines[line]) end
    out[#out + 1] = ("LF:%d"):format(file.total)
    out[#out + 1] = ("LH:%d"):format(file.covered)
    out[#out + 1] = "end_of_record"
  end
  return #out == 0 and "" or table.concat(out, "\n") .. "\n"
end

LineCoverage.executable_lines = executable_lines
LineCoverage.normalise = normalise

return core.finalise(LineCoverage)
