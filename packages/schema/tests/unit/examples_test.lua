-- The examples included in the reference pages are tested files: each one runs without error
-- and prints what its `-- Prints:` block says (the lines that follow it, each starting with `-- `,
-- continue the expected output).
local test = require("harness.test")
local T = test.Case("ExamplesTest")

local here = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
local directory = here:match("^(.*)/tests/unit/") .. "/examples"
local NAMES = {
  "hecate.schema.validate",
  "hecate.schema.to_json_schema",
  "hecate.schema.string",
  "hecate.schema.integer",
  "hecate.schema.map",
  "hecate.schema.enumeration",
  "hecate.schema.tagged_union",
  "hecate.schema.of",
  "hecate.schema.Schema.build",
  "hecate.schema.default",
  "hecate.schema.sent",
}

--- The text a `-- Prints:` block expects.
---@param source string
---@return string?
local function expected_output(source)
  local lines, collecting = {}, false
  for line in (source .. "\n"):gmatch("(.-)\r?\n") do
    local first = line:match("^%-%- Prints: ?(.*)$")
    if first then
      collecting = true
      lines[#lines + 1] = first
    elseif collecting then
      local more = line:match("^%-%- ?(.*)$")
      if more == nil then break end
      lines[#lines + 1] = more
    end
  end
  if #lines == 0 then return nil end
  return table.concat(lines, "\n")
end

function T:test_every_example_runs_and_prints_what_it_says()
  for _, name in ipairs(NAMES) do
    local path = ("%s/%s.lua"):format(directory, name)
    local file = assert(io.open(path, "rb"))
    local source = file:read("a")
    file:close()
    local expected = expected_output(source)
    self:assert_not_nil(expected, path .. " has no `-- Prints:` line")
    local lines = {}
    local environment = setmetatable({ print = function(...)
      local parts = table.pack(...)
      for i = 1, parts.n do parts[i] = tostring(parts[i]) end
      lines[#lines + 1] = table.concat(parts, "\t")
    end }, { __index = _G })
    local chunk = assert(load(source, "@" .. path, "t", environment))
    chunk()
    self:assert_equal(expected, table.concat(lines, "\n"), path)
  end
end

return T
