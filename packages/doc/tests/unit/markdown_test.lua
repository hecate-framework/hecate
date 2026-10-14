local test = require("harness.test")
local markdown = require("hecate.doc.markdown")
local T = test.Case("MarkdownTest")

local function render(source, options) return markdown.render(source, options).html end

function T:check(source, expected, options)
  self:assert_equal(expected, render(source, options))
end

-- Inline constructs (CommonMark 0.31, sections 6.1 to 6.8) --------------------------------

function T:test_emphasis_and_strong()
  self:check("*foo bar*", "<p><em>foo bar</em></p>")
  self:check("**foo bar**", "<p><strong>foo bar</strong></p>")
  self:check("***strong emph***", "<p><em><strong>strong emph</strong></em></p>")
  self:check("*foo**bar**baz*", "<p><em>foo<strong>bar</strong>baz</em></p>")
  self:check("foo*bar*", "<p>foo<em>bar</em></p>")
  self:check("5*6*78", "<p>5<em>6</em>78</p>")
end

function T:test_left_and_right_flanking_rules_reject_isolated_delimiters()
  self:check("a * foo bar*", "<p>a * foo bar*</p>")
  self:check("** foo bar**", "<p>** foo bar**</p>")
  self:check("_ foo bar_", "<p>_ foo bar_</p>")
end

function T:test_underscore_does_not_emphasise_inside_words()
  self:check("snake_case_word", "<p>snake_case_word</p>")
  self:check("foo_bar_", "<p>foo_bar_</p>")
  self:check("_foo_bar_baz_", "<p><em>foo_bar_baz</em></p>")
end

function T:test_strikethrough_needs_two_tildes()
  self:check("~~gone~~", "<p><del>gone</del></p>")
  self:check("~one~", "<p>~one~</p>")
end

function T:test_code_spans()
  self:check("`foo`", "<p><code>foo</code></p>")
  self:check("`` foo ` bar ``", "<p><code>foo ` bar</code></p>")
  self:check("`<b>`", "<p><code>&lt;b&gt;</code></p>")
  self:check("`unclosed", "<p>`unclosed</p>")
  self:check("*not `*` emphasis*", "<p><em>not <code>*</code> emphasis</em></p>")
end

function T:test_backslash_escapes_and_entities()
  self:check("\\*not emphasis\\*", "<p>*not emphasis*</p>")
  self:check("a \\q b", "<p>a \\q b</p>")
  self:check("&amp; & &copy;", "<p>&amp; &amp; &copy;</p>")
end

function T:test_hard_and_soft_breaks()
  self:check("a  \nb", "<p>a<br>\nb</p>")
  self:check("a\\\nb", "<p>a<br>\nb</p>")
  self:check("a\nb", "<p>a\nb</p>")
end

function T:test_inline_links_with_titles_and_angle_destinations()
  self:check('[link](/uri "title")', '<p><a href="/uri" title="title">link</a></p>')
  self:check("[link](</my uri>)", '<p><a href="/my%20uri">link</a></p>')
  self:check("[link]()", '<p><a href="">link</a></p>')
  self:check("[link](foo(and(bar)))", '<p><a href="foo(and(bar))">link</a></p>')
  self:check("[a *b* c](u)", '<p><a href="u">a <em>b</em> c</a></p>')
end

function T:test_links_do_not_nest()
  self:check("[a [b](c) d](e)", '<p>[a <a href="c">b</a> d](e)</p>')
end

function T:test_reference_links_use_definitions()
  self:check('[foo]: /url "T"\n\n[foo], [bar][FOO] and [x][]\n\n[x]: /x',
    '<p><a href="/url" title="T">foo</a>, <a href="/url" title="T">bar</a> and <a href="/x">x</a></p>')
  self:check("[missing]", "<p>[missing]</p>")
end

function T:test_images_and_autolinks()
  self:check("![alt *text*](a.png \"t\")",
    '<p><img src="a.png" alt="alt text" title="t" loading="lazy" decoding="async"></p>')
  self:check("<https://example.com/a?b=1&c=2>",
    '<p><a href="https://example.com/a?b=1&amp;c=2">https://example.com/a?b=1&amp;c=2</a></p>')
  self:check("<me@example.com>", '<p><a href="mailto:me@example.com">me@example.com</a></p>')
end

-- Blocks ----------------------------------------------------------------------------------

function T:test_atx_and_setext_headings_get_unique_anchors()
  local result = markdown.render("# One\n\n## Two\n\n## Two\n\nThree\n-----\n\n#### Four ####")
  local ids = {}
  for _, heading in ipairs(result.headings) do ids[#ids + 1] = heading.level .. ":" .. heading.id end
  self:assert_equal("1:one,2:two,2:two-1,2:three,4:four", table.concat(ids, ","))
  self:assert_true(result.html:find('<h2 id="two-1" tabindex="-1">Two<a class="header-anchor" href="#two-1"', 1, true) ~= nil)
end

function T:test_heading_ids_keep_accents_and_accept_custom_ids()
  local result = markdown.render("## Réacteur et Échéance\n\n## Section {#custom-id}")
  self:assert_equal("réacteur-et-échéance", result.headings[1].id)
  self:assert_equal("custom-id", result.headings[2].id)
  self:assert_equal("Section", result.headings[2].text)
end

function T:test_seven_hashes_or_no_space_is_not_a_heading()
  self:check("####### x", "<p>####### x</p>")
  self:check("#hashtag", "<p>#hashtag</p>")
end

function T:test_thematic_breaks()
  self:check("***", "<hr>")
  self:check("- - -", "<hr>")
  self:check("a\n\n___\n\nb", "<p>a</p>\n<hr>\n<p>b</p>")
end

function T:test_fenced_code_keeps_content_verbatim_and_labels_the_language()
  local html = render("```lua\nlocal x = \"<b>\"\n```")
  self:assert_true(html:find('data-language="lua"', 1, true) ~= nil)
  self:assert_true(html:find('<span class="code-language">Lua</span>', 1, true) ~= nil)
  self:assert_true(html:find("&lt;b&gt;", 1, true) ~= nil)
  self:assert_true(html:find("<b>", 1, true) == nil)
end

function T:test_fence_closing_needs_the_same_character_and_enough_length()
  local html = render("````\n```\nstill code\n````\n\nafter")
  self:assert_true(html:find("still code", 1, true) ~= nil)
  self:assert_true(html:find("<p>after</p>", 1, true) ~= nil)
end

function T:test_unclosed_fence_runs_to_the_end_of_the_document()
  local html = render("```\ncode\nmore")
  self:assert_true(html:find("code\nmore", 1, true) ~= nil)
end

function T:test_indented_code_block()
  self:check("    a < b", '<div class="code-block"><div class="code-toolbar"></div><pre tabindex="0"><code>a &lt; b</code></pre></div>')
end

function T:test_block_quote_with_lazy_continuation_and_nesting()
  self:check("> a\nb\n> > c", "<blockquote>\n<p>a\nb</p>\n<blockquote>\n<p>c</p>\n</blockquote>\n</blockquote>")
end

function T:test_tight_list_has_no_paragraphs()
  self:check("- a\n- b", "<ul>\n<li>a</li>\n<li>b</li>\n</ul>")
end

function T:test_loose_list_has_paragraphs()
  self:check("- a\n\n- b", "<ul>\n<li><p>a</p></li>\n<li><p>b</p></li>\n</ul>")
  self:check("- a\n\n  b", "<ul>\n<li><p>a</p>\n<p>b</p></li>\n</ul>")
end

function T:test_ordered_list_keeps_its_start_number()
  self:check("3. a\n4. b", '<ol start="3">\n<li>a</li>\n<li>b</li>\n</ol>')
end

function T:test_nested_lists()
  self:check("- a\n  - b\n- c", "<ul>\n<li>a\n<ul>\n<li>b</li>\n</ul></li>\n<li>c</li>\n</ul>")
end

function T:test_list_item_with_a_fenced_code_block()
  local html = render("- step\n\n  ```sh\n  echo hi\n  ```\n- next")
  self:assert_true(html:find("<li><p>step</p>\n<div class=\"code-block\"", 1, true) ~= nil)
  self:assert_true(html:find("echo", 1, true) ~= nil)
end

function T:test_changing_the_bullet_starts_a_new_list()
  self:check("- a\n* b", "<ul>\n<li>a</li>\n</ul>\n<ul>\n<li>b</li>\n</ul>")
end

function T:test_task_list_items()
  local html = render("- [x] done\n- [ ] todo")
  self:assert_true(html:find('<ul class="contains-task-list">', 1, true) ~= nil)
  self:assert_true(html:find('<li class="task-list-item"><input type="checkbox" disabled checked> done</li>', 1, true) ~= nil)
  self:assert_true(html:find('<input type="checkbox" disabled> todo', 1, true) ~= nil)
end

function T:test_a_checkbox_goes_inside_the_paragraph_of_a_loose_task_item()
  local html = render("- [x] one\n\n- [ ] two")
  self:assert_true(html:find('<li class="task-list-item"><p><input type="checkbox" disabled checked> one</p></li>', 1, true) ~= nil)
end

function T:test_tables_with_alignment_and_escaped_pipes()
  local html = render("| A | B |\n|:--|--:|\n| `x\\|y` | 2 |\n| only |")
  self:assert_true(html:find('<th scope="col" class="align-left">A</th>', 1, true) ~= nil)
  self:assert_true(html:find('<th scope="col" class="align-right">B</th>', 1, true) ~= nil)
  self:assert_true(html:find("<code>x|y</code>", 1, true) ~= nil)
  self:assert_true(html:find('<td class="align-right"></td>', 1, true) ~= nil, "short rows are padded")
  self:assert_true(html:find('<div class="table-wrap">', 1, true) ~= nil)
end

function T:test_a_table_needs_a_delimiter_row_with_matching_columns()
  self:check("| a | b |\n|---|\n", "<p>| a | b |\n|---|</p>")
end

function T:test_containers_render_callouts_with_default_and_custom_titles()
  self:check("::: tip\nUse `x`.\n:::",
    '<div class="callout callout-tip" role="note">\n<p class="callout-title">Tip</p>\n<p>Use <code>x</code>.</p>\n</div>')
  local html = render("::: danger Data loss\ntext\n:::")
  self:assert_true(html:find('<p class="callout-title">Data loss</p>', 1, true) ~= nil)
  self:assert_true(html:find("callout-danger", 1, true) ~= nil)
end

function T:test_containers_use_localised_labels()
  local html = render("::: warning\nx\n:::", { labels = { warning = "Attention" } })
  self:assert_true(html:find('<p class="callout-title">Attention</p>', 1, true) ~= nil)
end

function T:test_containers_nest_with_longer_fences_and_hold_code()
  local html = render(":::: note\nouter\n\n::: tip\ninner\n:::\n\n```\n:::\n```\n::::\n\nafter")
  self:assert_true(html:find("callout-note", 1, true) ~= nil)
  self:assert_true(html:find("callout-tip", 1, true) ~= nil)
  self:assert_true(html:find("<p>after</p>", 1, true) ~= nil)
  local _, count = html:gsub('class="callout ', "")
  self:assert_equal(2, count)
end

function T:test_unknown_container_names_stay_text()
  self:check("::: banana\nx\n:::", "<p>::: banana\nx\n:::</p>")
end

function T:test_html_comments_are_dropped()
  self:check("<!-- generated: do not edit -->\n\ntext\n\n<!--\nmulti\nline\n-->\n\nend", "<p>text</p>\n<p>end</p>")
  self:check("a <!-- c --> b", "<p>a  b</p>")
end

-- Results ---------------------------------------------------------------------------------

function T:test_strip_title_removes_a_leading_level_one_heading()
  local result = markdown.render("# The *title*\n\nbody\n\n## Next", { strip_title = true })
  self:assert_equal("The title", result.title)
  self:assert_equal("<p>body</p>\n" .. result.html:match("<h2.*"), result.html)
  self:assert_equal(1, #result.headings)
  local kept = markdown.render("intro\n\n# Later", { strip_title = true })
  self:assert_nil(kept.title)
end

function T:test_sections_split_at_second_and_third_level_headings()
  local result = markdown.render("intro text\n\n## A\n\nalpha *one*\n\n### B\n\nbeta `two`\n\n## C\n\n- gamma")
  self:assert_equal(4, #result.sections)
  self:assert_nil(result.sections[1].id)
  self:assert_equal("intro text", result.sections[1].text)
  self:assert_equal("a", result.sections[2].id)
  self:assert_equal("alpha one", result.sections[2].text)
  self:assert_equal("beta two", result.sections[3].text)
  self:assert_equal(3, result.sections[3].level)
  self:assert_equal("gamma", result.sections[4].text)
end

function T:test_links_are_collected_and_rewritten()
  local result = markdown.render("[a](x.md) ![i](p.png) <https://e.test> [r][k]\n\n[k]: y.md", {
    resolve_link = function(href) return "/base/" .. href end,
  })
  self:assert_equal("x.md,p.png,https://e.test,y.md", table.concat(result.links, ","))
  self:assert_true(result.html:find('href="/base/x.md"', 1, true) ~= nil)
  self:assert_true(result.html:find('src="/base/p.png"', 1, true) ~= nil)
  self:assert_true(result.html:find('href="/base/y.md"', 1, true) ~= nil)
end

function T:test_crlf_bom_and_tabs_are_accepted()
  self:check("\xEF\xBB\xBF# T\r\n\r\n-\ta\r\n-\tb\r\n", "<h1 id=\"t\" tabindex=\"-1\">T<a class=\"header-anchor\" href=\"#t\" aria-label=\"Permalink to “T”\"></a></h1>\n<ul>\n<li>a</li>\n<li>b</li>\n</ul>")
end

function T:test_empty_document_renders_nothing()
  self:check("", "")
  self:check("\n\n  \n", "")
end

function T:test_rendering_is_deterministic()
  local source = "# A\n\n- x\n- y\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n::: tip\nt\n:::\n"
  self:assert_equal(render(source), render(source))
end

return T
