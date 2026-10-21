-- The Lua contract of the renderer (comrak behind hecate.doc.markdown, ADR 0022). CommonMark and
-- GFM conformance is comrak's; what is tested here is what hecate.doc adds on top of it.
local test = require("harness.test")
local markdown = require("hecate.doc.markdown")
local T = test.Case("MarkdownTest")

local function has(text, part) return text:find(part, 1, true) ~= nil end

function T:test_gfm_constructs_render()
  local html = markdown.render("| a | b |\n|:-|-:|\n| 1 | 2 |\n\n- [x] done\n\n~~gone~~ and www.example.com\n").html
  self:assert_true(has(html, "<table>"))
  self:assert_true(has(html, 'type="checkbox"'))
  self:assert_true(has(html, "<del>gone</del>"))
  self:assert_true(has(html, '<a href="http://www.example.com">'))
end

function T:test_headings_have_unique_ids_anchors_and_custom_ids()
  local result = markdown.render("## Same\n\n## Same\n\n## Named {#mine}\n")
  self:assert_equal(3, #result.headings)
  self:assert_equal("same", result.headings[1].id)
  self:assert_equal("same-1", result.headings[2].id)
  self:assert_equal("mine", result.headings[3].id)
  self:assert_equal("Named", result.headings[3].text)
  self:assert_true(has(result.html, '<h2 id="same-1" tabindex="-1">Same<a class="header-anchor" href="#same-1"'))
  self:assert_true(not has(markdown.render("## Same\n", { heading_anchors = false }).html, "header-anchor"))
end

function T:test_a_leading_title_can_be_stripped()
  local result = markdown.render("<!-- generated -->\n\n# The title\n\nBody\n\n## Part\n\nMore\n", { strip_title = true })
  self:assert_equal("The title", result.title)
  self:assert_true(not has(result.html, "The title"))
  self:assert_equal(1, #result.headings)
  self:assert_equal("Body", result.sections[1].text)
  self:assert_equal("part", result.sections[2].id)
  self:assert_equal("More", result.sections[2].text)
  self:assert_equal(nil, markdown.render("# Kept\n").title)
end

function T:test_callouts_are_alerts_with_localised_default_titles()
  local html = markdown.render("> [!NOTE]\n> a\n\n> [!TIP] Mine\n> b\n", { labels = { note = "Remarque", tip = "Astuce" } }).html
  self:assert_true(has(html, "markdown-alert-note"))
  self:assert_true(has(html, "Remarque"))
  self:assert_true(has(html, "Mine"))
  self:assert_true(not has(html, "Astuce"))
end

function T:test_links_and_images_are_listed_and_rewritten()
  local result = markdown.render("[a](x.md) ![b](y.png)", {
    resolve_link = function(href) return "/base/" .. href end,
  })
  self:assert_true(has(result.html, 'href="/base/x.md"'))
  self:assert_true(has(result.html, 'src="/base/y.png"'))
  self:assert_equal("x.md", result.links[1])
  self:assert_equal("y.png", result.links[2])
end

function T:test_an_error_in_the_link_resolver_propagates()
  local ok, message = pcall(markdown.render, "[a](x.md)", { resolve_link = function() error("boom", 0) end })
  self:assert_true(not ok)
  self:assert_true(has(tostring(message), "boom"))
end

function T:test_code_blocks_get_a_toolbar_and_highlighting()
  local html = markdown.render("```lua\nlocal x <const> = 1\n```\n").html
  self:assert_true(has(html, '<div class="code-block" data-language="lua">'))
  self:assert_true(has(html, '<span class="code-language">Lua</span>'))
  self:assert_true(has(html, '<code class="language-lua">'))
  self:assert_true(has(html, 'class="hl-'))
  self:assert_true(not has(html, "style="))
  local plain = markdown.render("```lua\nlocal x <const> = 1\n```\n", { highlight = false }).html
  self:assert_true(has(plain, "local x &lt;const&gt; = 1"))
  self:assert_true(not has(plain, "hl-"))
end

function T:test_raw_html_is_text_comments_are_dropped_and_script_links_are_not_links()
  local html = markdown.render("<!-- c -->\n\nRaw <b>x</b>\n\n<div>block</div>\n\n[bad](javascript:alert(1))\n").html
  self:assert_true(not has(html, "<b>"))
  self:assert_true(not has(html, "<div>"))
  self:assert_true(not has(html, "<!--"))
  self:assert_true(not has(html, "javascript:"))
  self:assert_true(has(html, "&lt;b&gt;x&lt;/b&gt;"))
end

return T
