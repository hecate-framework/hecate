-- The examples included in the website pages are tested files: each one runs without error and prints what its
-- `-- Prints:` block says (the lines that follow it, each starting with `-- `, continue the expected output).
local test = require("harness.test")
local T = test.Case("ConfigExamplesTest")

local here = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
local directory = here:match("^(.*)/tests/unit/") .. "/examples"
local NAMES = { "hecate.config.load" }

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
  return table.concat(lines, "\n") .. "\n"
end

for _, name in ipairs(NAMES) do
  T["test_example_" .. name:gsub("%.", "_")] = function(self)
    local path = directory .. "/" .. name .. ".lua"
    local file = assert(io.open(path, "rb"))
    local source = file:read("a")
    file:close()
    local chunk = assert(load(source, "@" .. path))
    local printed = {}
    local real_print = print
    ---@diagnostic disable-next-line: lowercase-global
    print = function(...)
      local parts = table.pack(...)
      for i = 1, parts.n do parts[i] = tostring(parts[i]) end
      printed[#printed + 1] = table.concat(parts, "\t")
    end
    local ok, err = pcall(chunk)
    print = real_print
    self:assert_true(ok, tostring(err))
    self:assert_equal(expected_output(source), table.concat(printed, "\n") .. "\n")
  end
end

return T
