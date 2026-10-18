local test = require("harness.test")
local docs_examples = require("lib.docs_examples")
local T = test.Case("DocsExamplesTest")

local FILES = { ["packages/x/examples/a.lua"] = "print('a')\n-- Prints: a\n" }
local function read(path) return FILES[path] end
local function page(body) return "# Title\n\n" .. body end

function T:test_a_block_that_matches_its_file_passes()
  local text = page("<!-- example: packages/x/examples/a.lua -->\n```lua\nprint('a')\n-- Prints: a\n```\n\nAfter.\n")
  self:assert_equal(0, #docs_examples.check(text, read))
end

function T:test_a_block_that_differs_is_reported_with_the_line_of_the_marker()
  local text = page("<!-- example: packages/x/examples/a.lua -->\n```lua\nprint('b')\n```\n")
  local problems = docs_examples.check(text, read)
  self:assert_equal(1, #problems)
  self:assert_equal(3, problems[1].line)
  self:assert_not_nil(problems[1].message:find("differs", 1, true))
end

function T:test_a_missing_file_is_reported()
  local text = page("<!-- example: packages/x/examples/none.lua -->\n```lua\nx\n```\n")
  local problems = docs_examples.check(text, read)
  self:assert_equal(1, #problems)
  self:assert_not_nil(problems[1].message:find("does not exist", 1, true))
end

function T:test_a_marker_without_a_fence_is_reported()
  local problems = docs_examples.check(page("<!-- example: packages/x/examples/a.lua -->\n\ntext\n"), read)
  self:assert_equal(1, #problems)
  self:assert_not_nil(problems[1].message:find("fenced", 1, true))
end

function T:test_an_unclosed_block_is_reported()
  local problems = docs_examples.check(page("<!-- example: packages/x/examples/a.lua -->\n```lua\nprint('a')\n"), read)
  self:assert_equal(1, #problems)
  self:assert_not_nil(problems[1].message:find("not closed", 1, true))
end

function T:test_line_endings_and_trailing_blank_lines_do_not_matter()
  local text = "<!-- example: packages/x/examples/a.lua -->\r\n```lua\r\nprint('a')\r\n-- Prints: a\r\n```\r\n"
  self:assert_equal(0, #docs_examples.check(text, read))
end

function T:test_a_page_without_markers_and_ordinary_comments_are_ignored()
  self:assert_equal(0, #docs_examples.check("<!-- a comment -->\n```lua\nx\n```\n", read))
end

function T:test_several_markers_are_checked_independently()
  local text = page("<!-- example: packages/x/examples/a.lua -->\n```lua\nprint('a')\n-- Prints: a\n```\n\n"
    .. "<!-- example: packages/x/examples/a.lua -->\n```lua\nold\n```\n")
  local problems = docs_examples.check(text, read)
  self:assert_equal(1, #problems)
  self:assert_equal(9, problems[1].line)
end

return T
