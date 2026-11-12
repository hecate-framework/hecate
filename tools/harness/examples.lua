-- Shared runner for the examples tests of every package (owner request, 2026-11-12;
-- `docs/architecture/documentation.md`, "Code examples"). An example is a tested file: it runs without error, and
-- what a line prints is written in a `-- Prints:` block directly under that line (the comment lines that follow
-- it, each starting with `-- `, continue the expected output). Output is never gathered at the end of the example.
--
-- Matching: each `print` is attributed to the innermost line of the example that is running when it is called. A
-- block expects the output of exactly one line, the last line printing before the block, and that line is followed
-- by the block with no blank or comment line in between (only the rest of its statement, such as `end)`).
local M = {}

--- The `-- Prints:` blocks of a source.
---@param source string
---@return { line: integer, last: integer, text: string }[] blocks  `line` is the line of `-- Prints:`, `last` its last
function M.expectations(source)
  local blocks, current = {}, nil
  local number = 0
  for line in (source .. "\n"):gmatch("(.-)\r?\n") do
    number = number + 1
    local first = line:match("^%s*%-%- Prints: ?(.*)$") or (line:match("^%s*%-%- Prints:$") and "")
    if first then
      current = { line = number, last = number, lines = { first } }
      blocks[#blocks + 1] = current
    elseif current then
      local more = line:match("^%s*%-%- ?(.*)$")
      if more == nil or line:match("^%s*%-%-%[") then
        current = nil
      else
        current.lines[#current.lines + 1] = more
        current.last = number
      end
    end
  end
  local result = {}
  for index, block in ipairs(blocks) do
    result[index] = { line = block.line, last = block.last, text = table.concat(block.lines, "\n") }
  end
  return result
end

--- Splits a source into lines.
---@param source string
---@return string[]
local function split(source)
  local lines = {}
  for line in (source .. "\n"):gmatch("(.-)\r?\n") do lines[#lines + 1] = line end
  return lines
end

--- Checks captured output against the blocks of a source.
---@param source string
---@param outputs { line: integer, text: string }[]  in the order they were printed
---@return string? problem  nil when the output is exactly what the blocks say, where they say it
function M.compare(source, outputs)
  local blocks, lines = M.expectations(source), split(source)
  if #blocks == 0 and #outputs == 0 then return "the example has no `-- Prints:` block" end
  local received = {}
  for _, output in ipairs(outputs) do
    local owner
    for index, block in ipairs(blocks) do
      if block.line > output.line then
        owner = index
        break
      end
    end
    if owner == nil then
      return ("line %d prints %q but no `-- Prints:` block follows it"):format(output.line, output.text)
    end
    local entry = received[owner]
    if entry == nil then
      entry = { from = output.line, texts = {} }
      received[owner] = entry
    elseif entry.from ~= output.line then
      return ("lines %d and %d print into the same `-- Prints:` block (line %d): give each its own block, directly "
        .. "under it"):format(entry.from, output.line, blocks[owner].line)
    end
    entry.texts[#entry.texts + 1] = output.text
  end
  for index, block in ipairs(blocks) do
    local entry = received[index]
    if entry == nil then
      return ("the `-- Prints:` block of line %d expects %q, but nothing printed it"):format(block.line, block.text)
    end
    for between = entry.from + 1, block.line - 1 do
      local text = lines[between]
      if text:match("^%s*$") or text:match("^%s*%-%-") then
        return ("the `-- Prints:` block of line %d is not directly under line %d, which prints it"):format(
          block.line, entry.from)
      end
    end
    local actual = table.concat(entry.texts, "\n")
    if actual ~= block.text then
      return ("the `-- Prints:` block of line %d expects %q, line %d printed %q"):format(
        block.line, block.text, entry.from, actual)
    end
  end
  return nil
end

--- Runs an example file and checks its output.
---@param path string
---@param globals table?  extra globals of the example's environment (for example a patched `require`)
---@return string? problem  nil when it ran and printed what its blocks say
function M.run(path, globals)
  local file = assert(io.open(path, "rb"))
  local source = file:read("a")
  file:close()
  local chunkname = "@" .. path
  local outputs = {}
  local environment = {}
  for key, value in pairs(globals or {}) do environment[key] = value end
  environment.print = function(...)
    local parts = table.pack(...)
    for i = 1, parts.n do parts[i] = tostring(parts[i]) end
    local line = 0
    for level = 2, 200 do
      local info = debug.getinfo(level, "Sl")
      if info == nil then break end
      if info.source == chunkname then
        line = info.currentline
        break
      end
    end
    for text in (table.concat(parts, "\t") .. "\n"):gmatch("(.-)\n") do
      outputs[#outputs + 1] = { line = line, text = text }
    end
  end
  setmetatable(environment, { __index = _G })
  local chunk, message = load(source, chunkname, "t", environment)
  if not chunk then return message end
  local ok, failure = xpcall(chunk, debug.traceback)
  if not ok then return tostring(failure) end
  local problem = M.compare(source, outputs)
  return problem and (path .. ": " .. problem) or nil
end

--- Runs the named examples of a package directory and fails the case with every problem found.
---@param case table  the running test case (`self`)
---@param directory string  the package's `examples` directory
---@param names string[]  example names, without `.lua`
---@param globals table?  extra globals for every example
function M.check(case, directory, names, globals)
  local problems = {}
  for _, name in ipairs(names) do
    problems[#problems + 1] = M.run(("%s/%s.lua"):format(directory, name), globals)
  end
  if #problems > 0 then case:fail(table.concat(problems, "\n")) end
end

return M
