local test = require("harness.test")
local highlight = require("hecate.doc.highlight")
local T = test.Case("HighlightTest")

function T:test_known_languages_are_highlighted_with_prefixed_classes()
  local out = highlight.render("lua", "local n = 1 -- c\n")
  self:assert_true(out:find('class="hl-', 1, true) ~= nil)
  self:assert_nil(out:find("style=", 1, true))
  for _, language in ipairs({ "json", "sh", "http", "diff", "rust", "c", "sql", "yaml" }) do
    self:assert_true(highlight.supports(language), language)
  end
end

function T:test_unknown_languages_and_empty_code_are_escaped_and_plain()
  self:assert_equal("a &lt;b&gt; &amp; &quot;c&quot;", highlight.render("nonsense", 'a <b> & "c"'))
  self:assert_equal("", highlight.render("lua", ""))
  self:assert_false(highlight.supports("nonsense"))
end

function T:test_markup_in_code_cannot_escape()
  local out = highlight.render("html", "<script>alert(1)</script>")
  self:assert_nil(out:find("<script", 1, true))
end

return T
