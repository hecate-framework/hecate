-- Rules for code examples (pure functions). Owner request, 2026-11-12; `docs/architecture/documentation.md`,
-- "Code examples":
--   1. No line that holds a comment is longer than `M.WIDTH` characters, indentation and the code before the
--      comment included. Code lines may be longer. A line is exempted when the line just above it is a comment
--      holding `M.EXEMPTION`.
--   2. What a line makes the reader see is written in a `-- Prints:` block directly under that line; checked when
--      the examples run, by `tools/harness/examples.lua`.
local M = {}

--- Maximum width, in characters (UTF-8 code points), of a line that holds a comment.
M.WIDTH = 80

--- Text that, in a comment on the line just above, exempts a line from the width rule.
M.EXEMPTION = "check-examples: allow-long-comment"

--- Splits a text into lines, without their line endings.
---@param text string
---@return string[]
local function split(text)
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do lines[#lines + 1] = line end
  if lines[#lines] == "" then lines[#lines] = nil end
  return lines
end

--- Width of a line in characters; bytes when it is not valid UTF-8.
---@param line string
---@return integer
local function width(line)
  return utf8.len(line) or #line
end

--- Line numbers (1-based) of a Lua source that hold comment text, found by a tolerant lexer: strings, long
--- strings and long comments are honoured, so `--` inside a string is not a comment. Never fails on invalid code.
---@param source string
---@return table<integer, true> lines
---@return table<integer, string> comments  comment text per line (concatenated when a line holds several)
function M.comment_lines(source)
  local lines, comments = {}, {}
  local function mark(from, to, text)
    local first = 1
    for number = from, to do
      lines[number] = true
      local stop = text:find("\n", first, true)
      local piece = text:sub(first, (stop or #text + 1) - 1)
      comments[number] = (comments[number] or "") .. piece
      first = (stop or #text) + 1
    end
  end
  local position, line, length = 1, 1, #source
  local function count(from, to)
    local _, newlines = source:sub(from, to):gsub("\n", "")
    return newlines
  end
  while position <= length do
    local c = source:sub(position, position)
    if c == "\n" then
      line = line + 1
      position = position + 1
    elseif c == "-" and source:sub(position + 1, position + 1) == "-" then
      local level = source:match("^%[(=*)%[", position + 2)
      if level then
        local close = "]" .. level .. "]"
        local stop = source:find(close, position + 4 + #level, true)
        local last = stop and stop + #close - 1 or length
        local text = source:sub(position, last)
        local spanned = count(position, last)
        mark(line, line + spanned, text)
        line = line + spanned
        position = last + 1
      else
        local stop = source:find("\n", position, true) or length + 1
        mark(line, line, (source:sub(position, stop - 1):gsub("\r$", "")))
        position = stop
      end
    elseif c == "[" and source:match("^%[=*%[", position) then
      local level = source:match("^%[(=*)%[", position)
      local close = "]" .. level .. "]"
      local stop = source:find(close, position + 2 + #level, true)
      local last = stop and stop + #close - 1 or length
      line = line + count(position, last)
      position = last + 1
    elseif c == '"' or c == "'" then
      local cursor = position + 1
      while cursor <= length do
        local d = source:sub(cursor, cursor)
        if d == "\\" then
          if source:sub(cursor + 1, cursor + 1) == "\n" then line = line + 1 end
          cursor = cursor + 2
        elseif d == c then
          break
        elseif d == "\n" then
          break -- unfinished string: stop at the end of the line, as Lua would report it
        else
          cursor = cursor + 1
        end
      end
      position = cursor + 1
      if source:sub(cursor, cursor) == "\n" then
        position = cursor
      end
    else
      position = position + 1
    end
  end
  return lines, comments
end

--- Problems of the width rule in a Lua source.
---@param source string
---@return { line: integer, message: string }[] problems
function M.check_source(source)
  local problems = {}
  local holds, comments = M.comment_lines(source)
  for number, text in ipairs(split(source)) do
    local size = width(text)
    if holds[number] and size > M.WIDTH then
      local above = comments[number - 1]
      if not (above and above:find(M.EXEMPTION, 1, true)) then
        problems[#problems + 1] = {
          line = number,
          message = ("a line holding a comment is %d characters long (at most %d)"):format(size, M.WIDTH),
        }
      end
    end
  end
  return problems
end

--- The fenced Lua blocks of a Markdown text that are not copies of an example file (a block introduced by
--- `<!-- example: <path> -->` is checked through its file).
---@param text string
---@return { line: integer, source: string }[] blocks  `line` is the line of the first line of code
function M.lua_blocks(text)
  local lines, blocks = split(text), {}
  local index = 1
  while index <= #lines do
    local fence = lines[index]:match("^%s*(```+)%s*lua%s*$")
    if fence then
      local copied = index > 1 and lines[index - 1]:match("^<!%-%-%s*example:") ~= nil
      local body, cursor = {}, index + 1
      while cursor <= #lines and not lines[cursor]:match("^%s*" .. fence .. "%s*$") do
        body[#body + 1] = lines[cursor]
        cursor = cursor + 1
      end
      if not copied then blocks[#blocks + 1] = { line = index + 1, source = table.concat(body, "\n") } end
      index = cursor + 1
    else
      index = index + 1
    end
  end
  return blocks
end

--- Problems of the width rule in the Lua blocks of a Markdown text, with page line numbers.
---@param text string
---@return { line: integer, message: string }[] problems
function M.check_markdown(text)
  local problems = {}
  for _, block in ipairs(M.lua_blocks(text)) do
    for _, problem in ipairs(M.check_source(block.source)) do
      problems[#problems + 1] = { line = block.line + problem.line - 1, message = problem.message }
    end
  end
  return problems
end

return M
