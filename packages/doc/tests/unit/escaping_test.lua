---@diagnostic disable: need-check-nil  -- tests read files they have just built; a nil fails the assertion that follows
-- Invariant: output is escaped by default. Untrusted content must never become markup, an
-- event handler or a script URL, in the Markdown renderer, the theme and the search index.
local test = require("harness.test")
local doc = require("hecate.doc")
local html = require("hecate.doc.internal.html")
local T = test.Case("EscapingTest")

local function render(source) return doc.markdown.render(source).html end

function T:test_raw_html_is_shown_as_text()
  local out = render("<script>alert(1)</script>\n\n<img src=x onerror=alert(1)>\n\ntext <b>bold</b> <iframe>")
  self:assert_nil(out:find("<script", 1, true))
  self:assert_nil(out:find("<img", 1, true))
  self:assert_nil(out:find("<b>", 1, true))
  self:assert_nil(out:find("<iframe", 1, true))
  self:assert_true(out:find("&lt;script&gt;", 1, true) ~= nil)
end

function T:test_script_urls_never_reach_an_attribute()
  local attacks = {
    "[x](javascript:alert(1))", "[x](JaVaScRiPt:alert(1))", "[x](  javascript:alert(1))",
    "[x](java\tscript:alert(1))", "[x](vbscript:msgbox)", "[x](data:text/html;base64,PHNjcmlwdD4=)",
    "[x](<javascript:alert(1)>)", "![x](javascript:alert(1))", "<javascript:alert(1)>",
    "[x][r]\n\n[r]: javascript:alert(1)",
  }
  for _, attack in ipairs(attacks) do
    local out = render(attack)
    self:assert_nil(out:lower():find("href=\"%s*java"), attack)
    self:assert_nil(out:lower():find("src=\"%s*java"), attack)
    self:assert_nil(out:lower():find("href=\"%s*data"), attack)
    self:assert_nil(out:lower():find("href=\"%s*vbs"), attack)
  end
end

function T:test_safe_url_allow_list()
  for _, url in ipairs({ "https://a.test/x", "http://a.test", "mailto:a@b.test", "tel:+33", "/a/b", "a/b.md#c", "#top", "?q=1", "ftp://h/f" }) do
    self:assert_true(html.is_safe_url(url), url)
  end
  for _, url in ipairs({ "javascript:x", " JAVASCRIPT:x", "java\nscript:x", "data:text/plain,x", "vbscript:x", "file:///etc/passwd", "custom:thing" }) do
    self:assert_false(html.is_safe_url(url), url)
  end
end

function T:test_attribute_values_cannot_break_out()
  local out = render('[x](/a "t\\" onmouseover=\\"alert(1)")')
  self:assert_nil(out:find('" onmouseover', 1, true))
  self:assert_true(out:find("&quot;", 1, true) ~= nil)
  local img = render('![a" onerror="alert(1)](p.png)')
  self:assert_nil(img:find('" onerror', 1, true))
  local autolink = render('<https://a.test/"onmouseover="x>')
  self:assert_nil(autolink:find('"onmouseover', 1, true))
end

function T:test_code_and_language_labels_are_escaped()
  local out = render('```lua" onload="alert(1)\n<b>&\n```')
  self:assert_nil(out:find('onload="', 1, true))
  local fenced = render("```js\n</code></pre><script>alert(1)</script>\n```")
  self:assert_nil(fenced:find("<script", 1, true))
  local labelled = render('```a"b\nx\n```')
  self:assert_nil(labelled:find('data-language="a"b"', 1, true))
end

function T:test_heading_text_and_ids_are_escaped()
  local out = render('## <img src=x onerror=alert(1)> "quoted" & more {#id"x}')
  self:assert_nil(out:find("<img", 1, true))
  self:assert_nil(out:find('id="id"x', 1, true))
  self:assert_true(out:find("&lt;img", 1, true) ~= nil)
end

function T:test_table_cells_and_callout_titles_are_escaped()
  local table_html = render("| <b>h</b> |\n|---|\n| <i>c</i> |")
  self:assert_nil(table_html:find("<b>", 1, true))
  self:assert_nil(table_html:find("<i>", 1, true))
  local callout = render("> [!TIP] <script>x</script>\n> body")
  self:assert_nil(callout:find("<script", 1, true))
end

function T:test_entities_cannot_form_markup()
  local out = render("&lt;script&gt; &#60;script&#62;")
  self:assert_nil(out:find("<script", 1, true))
end

function T:test_the_page_title_and_description_are_escaped_in_the_theme()
  local fs = doc.MemoryFileSystem({
    ["c/en/index.md"] = '---\ntitle: "</title><script>alert(1)</script>"\ndescription: "\\"><script>alert(2)</script>"\n---\nbody',
  })
  doc.build({
    config = { title = 'Site "<b>"', description = "d" }, source = "c", out = "o", fs = fs,
  })
  local page = fs:read("o/en/index.html")
  self:assert_nil(page:find("<script>alert", 1, true))
  self:assert_nil(page:find("<b>", 1, true))
  self:assert_true(page:find("&lt;/title&gt;", 1, true) ~= nil)
end

function T:test_the_search_index_cannot_close_a_script_element()
  local encoded = doc.search.encode(doc.search.build("en", {
    { title = "</script><script>alert(1)</script>", url = "/en/x/", sections = { { text = "a & <b>" } } },
  }))
  self:assert_nil(encoded:find("<", 1, true))
  self:assert_nil(encoded:find(">", 1, true))
  self:assert_nil(encoded:find("&", 1, true))
end

return T
