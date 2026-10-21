-- Pure helpers of the `bench` task: discovery of benchmark files, parsing of their output and
-- summaries across runs. No file or process access here (the task injects it), so the tests need
-- no benchmark to run.
local M = {}

--- Describes a benchmark by the first comment line of its source.
---@param source string
---@return string description  empty when the file starts with no comment
function M.describe(source)
  local line = source:match("^%-%-%s*([^\r\n]*)")
  if not line then return "" end
  return (line:gsub("%s+$", ""))
end

--- Splits a benchmark output line into its label, value and unit.
--- A measurement line is a label, then a number, then a unit: `decode records native   312.4 MB/s`.
---@param line string
---@return string? label
---@return number? value
---@return string? unit
function M.parse_line(line)
  local label, value, unit = line:match("^%s*(%a.-)%s+(%-?%d+%.?%d*)%s+(%S+)")
  if not label then return nil end
  return label, tonumber(value), unit
end

--- Median of a sorted array.
---@param sorted number[]
---@return number
local function median(sorted)
  local n = #sorted
  if n % 2 == 1 then return sorted[(n + 1) // 2] end
  return (sorted[n // 2] + sorted[n // 2 + 1]) / 2
end

---@class hecate.tools.bench.Row
---@field label string
---@field unit string
---@field values number[]  one per run, in run order
---@field min number
---@field median number
---@field max number
---@field spread number  max / min (1.00 = identical runs)

--- Summarises the outputs of several runs of one benchmark, keeping the order of first appearance.
---@param outputs string[]  the text printed by each run
---@return hecate.tools.bench.Row[] rows
function M.summarise(outputs)
  local rows, by_label = {}, {}
  for _, text in ipairs(outputs) do
    for line in (text .. "\n"):gmatch("(.-)\r?\n") do
      local label, value, unit = M.parse_line(line)
      if label then
        local key = label .. "\0" .. unit
        local row = by_label[key]
        if not row then
          row = { label = label, unit = unit, values = {} }
          by_label[key] = row
          rows[#rows + 1] = row
        end
        row.values[#row.values + 1] = value
      end
    end
  end
  for _, row in ipairs(rows) do
    local sorted = { table.unpack(row.values) }
    table.sort(sorted)
    row.min, row.max, row.median = sorted[1], sorted[#sorted], median(sorted)
    row.spread = row.min ~= 0 and row.max / row.min or 0
  end
  return rows
end

--- Renders the rows of one benchmark as a Markdown table.
---@param rows hecate.tools.bench.Row[]
---@return string
function M.table(rows)
  local out = { "| Measure | Unit | Runs | Min | Median | Max | Max/min |", "|---|---|---|---|---|---|---|" }
  for _, row in ipairs(rows) do
    out[#out + 1] = ("| %s | %s | %d | %.4g | %.4g | %.4g | %.3f |"):format(
      row.label, row.unit, #row.values, row.min, row.median, row.max, row.spread)
  end
  return table.concat(out, "\n")
end

--- Parses a menu answer such as `1,3-4`, `a` (all) or `q` (quit).
---@param answer string
---@param count integer  number of entries of the menu
---@return integer[]? indexes  nil for quit or an invalid answer
---@return string? problem
function M.parse_selection(answer, count)
  answer = answer:gsub("%s+", "")
  if answer == "" or answer == "q" then return nil end
  local picked, seen = {}, {}
  local function add(i)
    if i < 1 or i > count then return false end
    if not seen[i] then seen[i] = true; picked[#picked + 1] = i end
    return true
  end
  if answer == "a" then
    for i = 1, count do add(i) end
    return picked
  end
  for part in answer:gmatch("[^,]+") do
    local low, high = part:match("^(%d+)%-(%d+)$")
    if not low then low = part:match("^(%d+)$"); high = low end
    if not low then return nil, ("cannot read '%s'"):format(part) end
    for i = tonumber(low), tonumber(high) do
      if not add(i) then return nil, ("no benchmark number %d"):format(i) end
    end
  end
  return picked
end

--- Checks a CPU list such as `2,3` or `2-3,6` for `taskset -c`.
---@param list string
---@return boolean
function M.valid_cpu_list(list)
  return list:match("^%d+[%d,%-]*$") ~= nil and not list:find(",,", 1, true) and not list:find("%-%-")
end

return M
