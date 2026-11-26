local test = require("harness.test")
local search = require("hecate.doc.search")
local T = test.Case("SearchTest")

local PAGE = {
  title = "Concurrency", url = "en/guide/concurrency/index.html", category = "Guide",
  sections = {
    { text = "Intro text" },
    { id = "futures", heading = "Futures", level = 2, text = "A future is a placeholder." },
    { id = "empty", heading = "Empty", level = 2, text = "" },
  },
}

function T:test_one_document_per_section_with_anchors()
  local index = search.build("en", { PAGE })
  self:assert_equal(search.FORMAT_VERSION, index.version)
  self:assert_equal("en", index.locale)
  self:assert_equal(3, #index.documents)
  self:assert_equal("en/guide/concurrency/index.html", index.documents[1].u, "the path below the root of the site, never root-relative")
  self:assert_nil(index.documents[1].h)
  self:assert_equal("en/guide/concurrency/index.html#futures", index.documents[2].u)
  self:assert_equal("Futures", index.documents[2].h)
  self:assert_equal("Guide", index.documents[2].c)
  self:assert_equal("en/guide/concurrency/index.html#empty", index.documents[3].u, "a heading is searchable without text")
end

function T:test_empty_leading_sections_are_left_out()
  local index = search.build("en", { { title = "T", url = "/t/", sections = { { text = "" }, { text = "x" } } } })
  self:assert_equal(1, #index.documents)
end

function T:test_text_is_truncated_on_a_character_boundary()
  local text = ("é"):rep(2000)
  local cut = search.truncate(text, 2401)
  self:assert_true(#cut <= 2401)
  self:assert_equal(0, #cut % 2, "no split two-byte character")
  self:assert_true(utf8.len(cut) ~= nil)
  self:assert_equal("abc", search.truncate("abc", 10))
  local index = search.build("en", { { title = "T", url = "/t/", sections = { { text = ("x"):rep(5000) } } } })
  self:assert_equal(search.MAX_TEXT, #index.documents[1].x)
end

function T:test_encoding_is_deterministic_valid_json_with_sorted_keys()
  local encoded = search.encode(search.build("fr", { PAGE }))
  self:assert_equal(encoded, search.encode(search.build("fr", { PAGE })))
  local expected = '{"documents":[{"c":"Guide","t":"Concurrency","u":"en/guide/concurrency/index.html","x":"Intro text"},'
  self:assert_equal(expected, encoded:sub(1, #expected))
  self:assert_true(encoded:find('"locale":"fr"', 1, true) ~= nil)
  self:assert_true(encoded:find('"version":1', 1, true) ~= nil)
end

function T:test_encoding_escapes_controls_and_quotes()
  local encoded = search.encode(search.build("en", {
    { title = 'a "q" \\ \n \t \1', url = "/t/", sections = { { text = "x" } } },
  }))
  self:assert_true(encoded:find('a \\"q\\" \\\\ \\n \\t \\u0001', 1, true) ~= nil)
end

function T:test_the_script_registers_the_index_for_its_locale_and_is_deterministic()
  local index = search.build("fr", { PAGE })
  local text = search.script(index)
  self:assert_equal(text, search.script(search.build("fr", { PAGE })))
  local prefix = '(window.hecateDocSearchIndex = window.hecateDocSearchIndex || {})["fr"] = '
  self:assert_equal(prefix, text:sub(1, #prefix))
  self:assert_equal(search.encode(index) .. ";\n", text:sub(#prefix + 1))
  self:assert_equal("hecateDocSearchIndex", search.REGISTRY)
end

function T:test_the_script_assigns_the_json_of_the_index_as_one_statement()
  local text = search.script(search.build("en", { PAGE }))
  -- JSON is a JavaScript expression: the file is one assignment of it.
  self:assert_true(text:find('["en"] = {"documents":[', 1, true) ~= nil)
  self:assert_equal(";\n", text:sub(-2))
  self:assert_equal(1, select(2, text:gsub("\n", "")), "one line")
end

return T
