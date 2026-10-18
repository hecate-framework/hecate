-- Golden file: fixtures/markdown/features.md rendered to fixtures/markdown/features.html.
-- To accept a deliberate change: HECATE_DOC_UPDATE_GOLDEN=1 lua tools/run.lua test doc
local test = require("harness.test")
local markdown = require("hecate.doc.markdown")
local T = test.Case("MarkdownGoldenTest")

local fixtures = (debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/unit/")) .. "/fixtures/markdown"

local function read(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local text = file:read("a")
  file:close()
  return text
end

function T:test_the_feature_sample_renders_to_the_golden_file()
  local actual = markdown.render(assert(read(fixtures .. "/features.md")), {
    resolve_link = function(href) return href end,
  }).html .. "\n"
  if os.getenv("HECATE_DOC_UPDATE_GOLDEN") then
    local file = assert(io.open(fixtures .. "/features.html", "wb"))
    file:write(actual)
    file:close()
  end
  local expected = read(fixtures .. "/features.html")
  self:assert_not_nil(expected, "missing golden file; run with HECATE_DOC_UPDATE_GOLDEN=1")
  self:assert_equal(expected, actual)
end

return T
