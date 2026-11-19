-- Limits of the native Markdown renderer: input size, output size, invalid UTF-8 and heading identifiers
-- (hecate.doc.native, ADR 0022). The Rust unit tests cover the functions; these cover the Lua binding.
local test = require("harness.test")
local markdown = require("hecate.doc.markdown")
local core = require("hecate.core")
local T = test.Case("MarkdownLimitsTest")

local function has(text, part) return text:find(part, 1, true) ~= nil end

local function refusal(self, source, options)
  local ok, err = pcall(markdown.render, source, options)
  self:assert_true(not ok)
  self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
  return tostring(err)
end

function T:test_the_limits_are_exposed_to_lua()
  self:assert_equal(8 * 1024 * 1024, markdown.MAX_INPUT_BYTES)
  self:assert_equal(100, markdown.MAX_NESTING)
  self:assert_equal(64 * 1024 * 1024, markdown.MAX_OUTPUT_BYTES)
  self:assert_equal(32, markdown.MAX_OUTPUT_RATIO)
end

function T:test_input_above_the_cap_is_refused_naming_the_limit_and_the_file()
  local message = refusal(self, ("a"):rep(markdown.MAX_INPUT_BYTES + 1), { file = "en/big.md" })
  self:assert_true(has(message, tostring(markdown.MAX_INPUT_BYTES)), message)
  self:assert_true(has(message, "8 MiB"), message)
  self:assert_true(has(message, "en/big.md"), message)
end

function T:test_a_fenced_sample_with_101_nested_quotes_is_rejected_and_100_is_accepted()
  local function fenced(depth) return "```\n" .. (">"):rep(depth) .. " x\n```\n" end
  local message = refusal(self, fenced(101))
  self:assert_true(has(message, "line 2"), message)
  self:assert_true(has(message, "100"), message)
  self:assert_true(has(markdown.render(fenced(100)).html, "x"))
end

function T:test_input_at_the_cap_renders()
  local source = ("a"):rep(markdown.MAX_INPUT_BYTES)
  self:assert_true(has(markdown.render(source).html, "<p>aaa"))
end

function T:test_invalid_utf8_names_the_position_and_the_file()
  local message = refusal(self, "ab\xFFcd", { file = "en/bad.md" })
  self:assert_true(has(message, "not valid UTF-8"), message)
  self:assert_true(has(message, "position 3"), message)
  self:assert_true(has(message, "en/bad.md"), message)
  self:assert_true(has(refusal(self, "tail \xC3"), "position 6"))
end

function T:test_the_native_entry_point_reports_invalid_utf8_without_raising()
  local native = require("hecate.doc.native")
  local result, message = native.render("x\xFF", nil)
  self:assert_nil(result)
  self:assert_true(has(message, "not valid UTF-8"), message)
  local ok, err = pcall(native.highlight, "x\xFF", "lua")
  self:assert_true(not ok)
  self:assert_true(has(tostring(err), "not valid UTF-8"), tostring(err))
end

function T:test_an_amplifying_document_is_refused_by_the_output_limit()
  local source = ("[^a]"):rep(100000) .. "\n\n[^a]: note\n"
  local message = refusal(self, source, { file = "en/amplify.md" })
  self:assert_true(has(message, "rendered HTML is larger than " .. tostring(markdown.MAX_OUTPUT_RATIO * #source)), message)
  self:assert_true(has(message, "en/amplify.md"), message)
end

function T:test_many_identical_headings_get_exact_ids_quickly()
  local count = 20000
  local started = os.clock()
  local result = markdown.render(("# h\n\n"):rep(count))
  self:assert_true(os.clock() - started < 20, "took too long")
  self:assert_equal(count, #result.headings)
  self:assert_equal("h", result.headings[1].id)
  self:assert_equal("h-1", result.headings[2].id)
  self:assert_equal("h-2", result.headings[3].id)
  self:assert_equal("h-" .. (count - 1), result.headings[count].id)
end

function T:test_a_custom_identifier_is_not_duplicated_by_a_generated_one()
  local result = markdown.render("# x {#h-1}\n\n# h\n\n# h\n")
  self:assert_equal("h-1", result.headings[1].id)
  self:assert_equal("h", result.headings[2].id)
  self:assert_equal("h-2", result.headings[3].id)
end

return T
