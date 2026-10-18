local test = require("harness.test")
local highlight = require("hecate.doc.highlight")
local T = test.Case("HighlightTest")

local function has(html, class, text)
  return html:find(('<span class="tk-%s">%s</span>'):format(class, text), 1, true) ~= nil
end

function T:test_lua_tokens_including_the_global_keyword_and_annotations()
  local out = highlight.render("lua", "---@async\nglobal <const> print\nlocal n = 0x1F + 1e3 -- c\nreturn nil, \"s\", [[l]]")
  self:assert_true(has(out, "annotation", "@async"))
  self:assert_true(has(out, "keyword", "global"))
  self:assert_true(has(out, "keyword", "local"))
  self:assert_true(has(out, "number", "0x1F"))
  self:assert_true(has(out, "number", "1e3"))
  self:assert_true(has(out, "comment", "-- c"))
  self:assert_true(has(out, "literal", "nil"))
  self:assert_true(has(out, "string", "&quot;s&quot;"))
  self:assert_true(has(out, "string", "[[l]]"))
end

function T:test_lua_long_comments_and_unterminated_strings_do_not_hang()
  local out = highlight.render("lua", "--[==[ a\n]] b ]==] x = 'oops\ny = 1")
  self:assert_true(out:find("tk-comment", 1, true) ~= nil)
  self:assert_true(has(out, "number", "1"))
end

function T:test_lua_identifiers_containing_keywords_are_not_split()
  local out = highlight.render("lua", "local endless, format = 1")
  self:assert_nil(out:find('tk-keyword">end<', 1, true))
end

function T:test_json_distinguishes_keys_from_values()
  local out = highlight.render("json", '{"a": [1, -2.5e3, true, null], "b": "x"}')
  self:assert_true(has(out, "property", "&quot;a&quot;"))
  self:assert_true(has(out, "string", "&quot;x&quot;"))
  self:assert_true(has(out, "number", "-2.5e3"))
  self:assert_true(has(out, "literal", "null"))
end

function T:test_shell_prompts_flags_variables_and_comments()
  local out = highlight.render("sh", "$ hecate new --name app | tee 'f' # go\necho $HOME ${X}")
  self:assert_true(has(out, "function", "hecate"))
  self:assert_true(has(out, "flag", "--name"))
  self:assert_true(has(out, "function", "tee"))
  self:assert_true(has(out, "comment", "# go"))
  self:assert_true(has(out, "variable", "$HOME"))
  self:assert_true(has(out, "variable", "${X}"))
end

function T:test_http_messages()
  local out = highlight.render("http", "POST /a HTTP/1.1\nHost: x\n\n{\"k\": 1}")
  self:assert_true(has(out, "keyword", "POST"))
  self:assert_true(has(out, "property", "Host"))
  self:assert_nil(out:find("tk-number", 1, true), "the body is left plain")
  self:assert_true(has(highlight.render("http", "HTTP/1.1 404 Not Found"), "number", "404"))
end

function T:test_diff_marks_inserted_and_deleted_lines()
  local out = highlight.render("diff", "@@ -1 +1 @@\n-a\n+b\n c")
  self:assert_true(has(out, "deleted", "-a"))
  self:assert_true(has(out, "inserted", "+b"))
  self:assert_true(has(out, "meta", "@@ -1 +1 @@"))
end

function T:test_unknown_languages_are_escaped_and_plain()
  self:assert_equal("&lt;a&gt; &amp;", highlight.render("klingon", "<a> &"))
  self:assert_equal("&lt;a&gt;", highlight.render("", "<a>"))
  self:assert_false(highlight.supports("klingon"))
  self:assert_true(highlight.supports("Lua"))
end

function T:test_labels()
  self:assert_equal("Lua", highlight.label("lua"))
  self:assert_equal("Shell", highlight.label("bash"))
  self:assert_equal("klingon", highlight.label("klingon"))
end

function T:test_output_never_contains_unescaped_angle_brackets_from_the_source()
  for _, language in ipairs({ "lua", "json", "sh", "http", "diff", "text" }) do
    local out = highlight.render(language, "<b>\"&'</b>")
    self:assert_nil(out:gsub('<span class="tk%-[%a]+">', ""):gsub("</span>", ""):find("<", 1, true), language)
  end
end

return T
