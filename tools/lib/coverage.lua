-- Helpers of the `coverage` task: which lines are executable, how hit records are read and how
-- reports and thresholds are produced. The harness records line hits (`harness/run_file.lua`).
local M = {}

--- Packages that must reach the threshold (`docs/architecture/automation.md`).
M.thresholds = { core = 90, reactor = 90, router = 90, schema = 90 }

--- Environment prefix that enables line recording into `dir` for a command.
---@param dir string
---@param windows boolean
---@return string
function M.environment(dir, windows)
  return windows and ("set HECATE_TEST_COVERAGE=%s&& "):format(dir) or ("HECATE_TEST_COVERAGE='%s' "):format(dir)
end

local structural = { ["end"] = true, ["else"] = true, ["do"] = true, ["then"] = true, ["repeat"] = true,
  ["}"] = true, ["{"] = true, [")"] = true, ["},"] = true, ["end)"] = true, ["end,"] = true, ["})"] = true }

--- Lines of a Lua source that hold code (an approximation of the debug line table: blank lines,
--- comments, long comments and lines made only of block delimiters are not executable).
---@param source string
---@return table<integer, true>
function M.executable_lines(source)
  local lines, long = {}, false
  local n = 0
  for line in (source .. "\n"):gmatch("(.-)\r?\n") do
    n = n + 1
    local text = line:match("^%s*(.-)%s*$")
    if long then
      if text:find("]]", 1, true) then long = false end
    elseif text:sub(1, 4) == "--[[" then
      if not text:find("]]", 5, true) then long = true end
    elseif text ~= "" and text:sub(1, 2) ~= "--" and not structural[text] then
      lines[n] = true
    end
  end
  return lines
end

--- Path with backslashes turned into slashes and `dir/..` segments collapsed.
---@param path string
---@return string
function M.normalise(path)
  path = path:gsub("\\", "/")
  local previous
  repeat
    previous = path
    path = path:gsub("[^/]+/%.%./", function(segment)
      return segment == "../../" and segment or ""
    end, 1)
  until path == previous
  return (path:gsub("^%./", ""))
end

--- Parses hit records ("<path>\t<line>" per line) into `{ [path] = { [line] = true } }`.
---@param text string
---@param into? table
---@return table<string, table<integer, true>>
function M.parse_hits(text, into)
  local hits = into or {}
  for raw, line in text:gmatch("([^\t\n]+)\t(%d+)") do
    local path = M.normalise(raw)
    local set = hits[path]
    if not set then set = {}; hits[path] = set end
    set[tonumber(line)] = true
  end
  return hits
end

--- Coverage of one file: executable and hit line counts (hits outside executable lines are ignored).
---@param executable table<integer, true>
---@param hit table<integer, true>?
---@return integer total
---@return integer covered
function M.count(executable, hit)
  local total, covered = 0, 0
  for line in pairs(executable) do
    total = total + 1
    if hit and hit[line] then covered = covered + 1 end
  end
  return total, covered
end

---@param total integer
---@param covered integer
---@return number
function M.percent(total, covered)
  return total == 0 and 100 or covered * 100 / total
end

--- LCOV text for files `{ { path =, executable =, hit = } ... }`, sorted by path.
---@param files table[]
---@return string
function M.lcov(files)
  table.sort(files, function(a, b) return a.path < b.path end)
  local out = {}
  for _, f in ipairs(files) do
    local numbers = {}
    for line in pairs(f.executable) do numbers[#numbers + 1] = line end
    table.sort(numbers)
    out[#out + 1] = "SF:" .. f.path
    local total, covered = M.count(f.executable, f.hit)
    for _, line in ipairs(numbers) do out[#out + 1] = ("DA:%d,%d"):format(line, f.hit and f.hit[line] and 1 or 0) end
    out[#out + 1] = "LF:" .. total
    out[#out + 1] = "LH:" .. covered
    out[#out + 1] = "end_of_record"
  end
  return table.concat(out, "\n") .. "\n"
end

--- Problems for packages under their threshold. `stats` is `{ [package] = { total =, covered = } }`.
---@param stats table<string, { total: integer, covered: integer }>
---@param thresholds? table<string, number>
---@return string[]
function M.check(stats, thresholds)
  local problems = {}
  for name, minimum in pairs(thresholds or M.thresholds) do
    local s = stats[name]
    if s and s.total > 0 then
      local pct = M.percent(s.total, s.covered)
      if pct < minimum then problems[#problems + 1] = ("%s: line coverage %.1f%% is under %d%%"):format(name, pct, minimum) end
    end
  end
  table.sort(problems)
  return problems
end

return M
