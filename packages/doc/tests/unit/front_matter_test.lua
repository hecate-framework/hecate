local test = require("harness.test")
local front_matter = require("hecate.doc.front_matter")
local core = require("hecate.core")
local doc = require("hecate.doc")
local T = test.Case("FrontMatterTest")

function T:test_page_without_front_matter_is_all_body()
  local meta, body = front_matter.parse("# Title\n\ntext")
  self:assert_nil(next(meta))
  self:assert_equal("# Title\n\ntext", body)
end

function T:test_scalars_quoted_strings_numbers_and_booleans()
  local meta, body = front_matter.parse(table.concat({
    "---", 'title: "A: quoted \\"title\\""', "plain: some words # comment", "single: 'it''s'", "order: 3",
    "negative: -2", "draft: false", "yes: true", "hecate: \"0.x\"", "---", "body", "",
  }, "\n"))
  self:assert_equal('A: quoted "title"', meta.title)
  self:assert_equal("some words", meta.plain)
  self:assert_equal("it's", meta.single)
  self:assert_equal(3, meta.order)
  self:assert_equal(-2, meta.negative)
  self:assert_equal(false, meta.draft)
  self:assert_equal(true, meta.yes)
  self:assert_equal("0.x", meta.hecate)
  self:assert_equal("body\n", body)
end

function T:test_inline_and_block_lists()
  local meta = front_matter.parse("---\ntags: [a, \"b, c\", 3]\nempty: []\nitems:\n  - one\n  - \"two\"\n---\n")
  self:assert_equal("a|b, c|3", table.concat(meta.tags, "|"))
  self:assert_equal(0, #meta.empty)
  self:assert_equal("one|two", table.concat(meta.items, "|"))
end

function T:test_crlf_and_bom_and_closing_dots()
  local meta, body = front_matter.parse("\xEF\xBB\xBF---\r\ntitle: T\r\n...\r\nbody")
  self:assert_equal("T", meta.title)
  self:assert_equal("body", body)
end

function T:test_a_horizontal_rule_later_in_the_body_is_not_front_matter()
  local meta, body = front_matter.parse("text\n\n---\ntitle: x\n---\n")
  self:assert_nil(next(meta))
  self:assert_true(body:find("title: x", 1, true) ~= nil)
end

function T:test_malformed_front_matter_raises_a_build_error_with_the_line()
  local function failure(source)
    local err = self:assert_error(function() front_matter.parse(source, "p.md") end)
    self:assert_true(core.is_instance_of(err, doc.BuildError))
    self:assert_equal("p.md", err.context.path)
    return err
  end
  failure("---\ntitle: x\n")
  self:assert_equal(3, failure("---\ntitle: x\nnot a pair\n---\n").context.line)
  self:assert_equal(3, failure("---\ntitle: x\ntitle: y\n---\n").context.line)
  failure('---\ntitle: "unterminated\n---\n')
end

return T
