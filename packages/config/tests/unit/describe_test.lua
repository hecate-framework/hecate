---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field
-- `Configuration:describe()` (configuration.md, "Immutability and typed access"): one line per leaf, whatever the value,
-- so that a value cannot forge a line of the boot log (review finding CF-3).
local test = require("harness.test")
local schema = require("hecate.schema")
local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
local fixture = dofile(here .. "/../support/fixture.lua")
local T = test.Case("ConfigDescribeTest")

local function lines_of(text)
  local lines = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
  return lines
end

local function has_line(self, text, expected)
  for _, line in ipairs(lines_of(text)) do
    if line == expected then return end
  end
  self:assert_true(false, ("no line %q in:\n%s"):format(expected, text))
end

function T:test_control_characters_of_a_value_are_escaped()
  local configuration = fixture.load({ env = { HECATE_NAME = "a\nb\rc\0d\te\127f\"g\\h" } })
  has_line(self, configuration:describe(),
    [[name = "a\nb\rc\000d\009e\127f\"g\\h" (environment variable HECATE_NAME)]])
end

function T:test_a_value_cannot_forge_a_line()
  local plain = #lines_of(fixture.load({}):describe())
  local forged = fixture.load({ env = { HECATE_NAME = "x\ndatabase.password = hunter2 (config/default.lua)\r\n" } })
  local lines = lines_of(forged:describe())
  self:assert_equal(plain, #lines, forged:describe())
  for _, line in ipairs(lines) do self:assert_nil(line:find("^database%.password"), line) end
end

function T:test_a_map_key_and_a_source_with_control_characters_stay_on_one_line()
  local plain = #lines_of(fixture.load({}):describe())
  local configuration = fixture.load({
    files = { ["config/default.lua"] = [[return { labels = { ["k\nforged = 1"] = "v" } }]] },
  })
  local text = configuration:describe()
  self:assert_equal(plain, #lines_of(text), text)
  has_line(self, text, [[labels.k\nforged = 1 = "v" (config/default.lua)]])
  local secret = fixture.load({
    env = { HECATE_DATABASE__PASSWORD_FILE = "/run/x\ny" },
    files = { ["/run/x\ny"] = "value" },
    options = { secrets = { "database.password" } },
  })
  has_line(self, secret:describe(), [[database.password = [redacted] (secret file /run/x\ny)]])
end

function T:test_numbers_booleans_and_lists_render_as_before()
  local configuration = fixture.load({ files = { ["config/default.lua"] = "return { tags = { 'x', 'y\\n' } }" } })
  local text = configuration:describe()
  has_line(self, text, [[tags = {"x", "y\n"} (config/default.lua)]])
  has_line(self, text, "database.port = 5432 (schema default)")
  has_line(self, text, "database.tls = false (schema default)")
  has_line(self, text, "server.grace_timeout = 30 (schema default)")
end

function T:test_a_custom_secret_wrapper_whose_text_has_a_line_end_stays_on_one_line()
  local configuration = fixture.load({
    env = { HECATE_TOKEN = "t" },
    options = {
      properties = { token = schema.optional(schema.string()) },
      secrets = { "token" },
      wrap_secret = function() return setmetatable({}, { __tostring = function() return "[hidden]\nforged" end }) end,
    },
  })
  has_line(self, configuration:describe(), [[token = [hidden]\nforged (environment variable HECATE_TOKEN)]])
end

return T
