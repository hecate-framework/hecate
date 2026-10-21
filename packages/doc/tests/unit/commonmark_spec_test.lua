-- The examples of the CommonMark 0.31.2 specification (https://github.com/commonmark/commonmark-spec,
-- CC BY-SA 4.0; downloaded by `lua tools/run.lua fetch-fixtures doc`, not vendored) run through the native
-- module with the options of the specification (no extension, raw HTML kept; OQ-37). The output is compared
-- as the specification asks: modulo whitespace between tags and inside them.
local test = require("harness.test")
local native = require("hecate.doc.native")
local T = test.Case("CommonMarkSpecTest")

local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
local fixtures = here .. "/../../../../.hecate/fixtures/doc/"
local path = fixtures .. "commonmark-spec/spec.txt"

-- Examples that comrak renders differently: "cm<number>" or "gfm<number>" (the order in spec.txt) -> reason.
local DEVIATIONS = {}

local EXAMPLES = 652
local FENCE = string.rep("`", 32)

local function examples(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local list, current, part = {}, nil, nil
  for line in file:lines() do
    local tag = line:match("^" .. FENCE .. " example ?(.*)$")
    if tag then
      current, part = { markdown = {}, html = {}, tag = tag }, "markdown"
    elseif current and line == FENCE then
      list[#list + 1] = {
        tag = current.tag,
        markdown = table.concat(current.markdown, "\n") .. "\n",
        html = table.concat(current.html, "\n") .. (#current.html > 0 and "\n" or ""),
      }
      current = nil
    elseif current and line == "." then
      part = "html"
    elseif current then
      current[part][#current[part] + 1] = (line:gsub("→", "\t"))
    end
  end
  file:close()
  return list
end

local function normalise(html)
  html = html:gsub("\r\n?", "\n")
  html = html:gsub(">%s+<", "><"):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
  html = html:gsub(" />", ">"):gsub(" >", ">"):gsub("< ", "<")
  return html
end

local function present(self, list, what)
  if list then return true end
  if os.getenv("CI") then self:fail("the " .. what .. " specification is missing (lua tools/run.lua fetch-fixtures doc)") end
  io.stderr:write("# skipped: the " .. what .. " specification is missing (lua tools/run.lua fetch-fixtures doc)\n")
  return false
end

local function differences(list, only_tagged)
  local failures, run = {}, 0
  for number, example in ipairs(list) do
    local extension = example.tag ~= "" and example.tag ~= "disabled" and example.tag or nil
    if not only_tagged or extension then
      run = run + 1
      local actual = native.commonmark(example.markdown, extension)
      if normalise(actual) ~= normalise(example.html) and not DEVIATIONS[(only_tagged and "gfm" or "cm") .. number] then
        failures[#failures + 1] = ("example %d: %q gave %q, expected %q"):format(number, example.markdown, actual, example.html)
      end
    end
  end
  return failures, run
end

function T:test_the_commonmark_examples_render_as_specified()
  local list = examples(path)
  if not present(self, list, "CommonMark") then return end
  self:assert_equal(EXAMPLES, #list, "the pinned specification has 652 examples")
  local failures = differences(list, false)
  self:assert_equal(0, #failures, #failures .. " example(s) differ:\n" .. table.concat(failures, "\n", 1, math.min(#failures, 20)))
end

function T:test_the_gfm_extension_examples_render_as_specified()
  local list = examples(fixtures .. "cmark-gfm/test/spec.txt")
  if not present(self, list, "GFM") then return end
  local failures, run = differences(list, true)
  self:assert_equal(22, run, "table (8), autolink (11), strikethrough (2) and tagfilter (1) examples")
  self:assert_equal(0, #failures, #failures .. " example(s) differ:\n" .. table.concat(failures, "\n", 1, math.min(#failures, 20)))
end

return T
