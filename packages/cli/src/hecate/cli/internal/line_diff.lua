-- A small line diff in the unified format (the output of `diff -u`), for `--force`: `hecate generate ...` shows what an
-- overwrite changes before it overwrites. `hecate.test` has only a structural diff of Lua values, not a text diff, so
-- this is the text one. The longest common subsequence of the lines between the common prefix and the common suffix;
-- past `MAX_CELLS` the middle is shown as one removal and one addition instead (still correct, less minimal).
global <const> table, ipairs, math, tostring

---@class hecate.cli.internal.line_diff
local M = {}

local CONTEXT = 3
local MAX_CELLS = 4000000

--- The lines of a text, each with its line terminator when it has one.
---@param text string
---@return string[]
local function split(text)
  local lines = {}
  for line in text:gmatch("[^\n]*\n?") do
    if line ~= "" then lines[#lines + 1] = line end
  end
  return lines
end

--- The edit script between two lists of lines: `{ tag, line }` with tag " ", "-" or "+".
---@param old string[]
---@param new string[]
---@return table[] script
local function script(old, new)
  local first = 1
  while first <= #old and first <= #new and old[first] == new[first] do first = first + 1 end
  local last_old, last_new = #old, #new
  while last_old >= first and last_new >= first and old[last_old] == new[last_new] do
    last_old, last_new = last_old - 1, last_new - 1
  end
  local out = {}
  for i = 1, first - 1 do out[#out + 1] = { " ", old[i] } end
  local rows, columns = last_old - first + 1, last_new - first + 1
  if rows * columns > MAX_CELLS then
    for i = first, last_old do out[#out + 1] = { "-", old[i] } end
    for j = first, last_new do out[#out + 1] = { "+", new[j] } end
  else
    -- lcs[i][j]: length of the common subsequence of old[i..last_old] and new[j..last_new].
    local lcs = {}
    for i = first, last_old + 1 do
      lcs[i] = {}
      for j = first, last_new + 1 do lcs[i][j] = 0 end
    end
    for i = last_old, first, -1 do
      for j = last_new, first, -1 do
        if old[i] == new[j] then lcs[i][j] = lcs[i + 1][j + 1] + 1
        else lcs[i][j] = math.max(lcs[i + 1][j], lcs[i][j + 1]) end
      end
    end
    local i, j = first, first
    while i <= last_old and j <= last_new do
      if old[i] == new[j] then out[#out + 1] = { " ", old[i] }; i, j = i + 1, j + 1
      elseif lcs[i + 1][j] >= lcs[i][j + 1] then out[#out + 1] = { "-", old[i] }; i = i + 1
      else out[#out + 1] = { "+", new[j] }; j = j + 1 end
    end
    while i <= last_old do out[#out + 1] = { "-", old[i] }; i = i + 1 end
    while j <= last_new do out[#out + 1] = { "+", new[j] }; j = j + 1 end
  end
  for i = last_old + 1, #old do out[#out + 1] = { " ", old[i] } end
  return out
end

--- One line of the output: the tag then the line without its terminator, and a marker when it had none.
---@param tag string
---@param line string
---@return string
local function render(tag, line)
  if line:sub(-1) == "\n" then return tag .. line:sub(1, -2) end
  return tag .. line .. "\n\\ No newline at end of file"
end

--- The range of a hunk header: `start,count`, with the count left out when it is 1 and the start one less when it is 0.
---@param start integer
---@param count integer
---@return string
local function range(start, count)
  if count == 1 then return tostring(start) end
  return start .. "," .. count
end

--- The unified diff of two texts, with three lines of context, or nil when they are equal.
---@param old string  the existing content
---@param new string  the new content
---@param old_name string  the name after `---`
---@param new_name string  the name after `+++`
---@return string? diff  no trailing line break; nil when `old == new`
function M.unified(old, new, old_name, new_name)
  if old == new then return nil end
  local steps = script(split(old), split(new))
  -- Positions of the changes, then hunks: runs of changes whose gaps are at most twice the context.
  local changes = {}
  for index, step in ipairs(steps) do
    if step[1] ~= " " then changes[#changes + 1] = index end
  end
  local out = { "--- " .. old_name, "+++ " .. new_name }
  local old_line, new_line = {}, {}
  local o, n = 1, 1
  for index, step in ipairs(steps) do
    old_line[index], new_line[index] = o, n
    if step[1] ~= "+" then o = o + 1 end
    if step[1] ~= "-" then n = n + 1 end
  end
  local position = 1
  while position <= #changes do
    local stop = position
    while changes[stop + 1] and changes[stop + 1] - changes[stop] - 1 <= 2 * CONTEXT do stop = stop + 1 end
    local from = math.max(1, changes[position] - CONTEXT)
    local to = math.min(#steps, changes[stop] + CONTEXT)
    local old_count, new_count = 0, 0
    for index = from, to do
      if steps[index][1] ~= "+" then old_count = old_count + 1 end
      if steps[index][1] ~= "-" then new_count = new_count + 1 end
    end
    local old_start = old_count == 0 and old_line[from] - 1 or old_line[from]
    local new_start = new_count == 0 and new_line[from] - 1 or new_line[from]
    out[#out + 1] = "@@ -" .. range(old_start, old_count) .. " +" .. range(new_start, new_count) .. " @@"
    for index = from, to do out[#out + 1] = render(steps[index][1], steps[index][2]) end
    position = stop + 1
  end
  return table.concat(out, "\n")
end

return M
