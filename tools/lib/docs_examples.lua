-- Code samples of the website that come from tested example files (pure functions; file access is
-- injected). A page includes a file by writing `<!-- example: <path> -->` on a line of its own,
-- immediately followed by a fenced code block holding the exact content of that file.
local M = {}

local MARKER = "^<!%-%-%s*example:%s*(%S+)%s*%-%->%s*$"

--- Normalises line endings and drops trailing blank lines.
---@param text string
---@return string
local function normalise(text)
  return (text:gsub("\r\n", "\n"):gsub("\n+$", ""))
end

--- Checks every example marker of a Markdown text.
---@param text string  the page
---@param read fun(path: string): string?  returns the content of a file, nil when it does not exist
---@return { line: integer, message: string }[] problems
function M.check(text, read)
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do lines[#lines + 1] = line end
  local problems = {}
  local function fail(line, message) problems[#problems + 1] = { line = line, message = message } end
  local index = 1
  while index <= #lines do
    local path = lines[index]:match(MARKER)
    if not path then
      index = index + 1
    else
      local marker = index
      local fence = (lines[index + 1] or ""):match("^(```+)[%w_%-]*%s*$")
      local source = read(path)
      if source == nil then fail(marker, ("the example file '%s' does not exist"):format(path)) end
      if not fence then
        fail(marker, "the marker is not followed by a fenced code block")
        index = index + 1
      else
        local body, closed = {}, nil
        local cursor = index + 2
        while cursor <= #lines do
          if lines[cursor]:match("^" .. fence .. "%s*$") then closed = cursor break end
          body[#body + 1] = lines[cursor]
          cursor = cursor + 1
        end
        if not closed then
          fail(marker, "the code block of the example is not closed")
          break
        end
        if source ~= nil and normalise(table.concat(body, "\n")) ~= normalise(source) then
          fail(marker, ("the code block differs from '%s': copy the file again"):format(path))
        end
        index = closed + 1
      end
    end
  end
  return problems
end

return M
