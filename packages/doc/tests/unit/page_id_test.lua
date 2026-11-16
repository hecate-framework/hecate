local test = require("harness.test")
local page_id = require("hecate.doc.internal.page_id")
local T = test.Case("PageIdTest")

function T:test_ordinary_ids_are_portable()
  for _, id in ipairs({ "index", "guide/concurrency", "guide/a.b", "référence/é", "a-b_c", "COM10", "CONSOLE", "x/com", ".x" }) do
    self:assert_nil(page_id.windows_problem(id), id)
  end
end

function T:test_reserved_characters_are_refused_in_any_segment()
  for _, character in ipairs({ "?", ":", "*", '"', "<", ">", "|", "\\", "\1", "\31" }) do
    self:assert_not_nil(page_id.windows_problem("a" .. character .. "b"), character)
    self:assert_not_nil(page_id.windows_problem("dir" .. character .. "/page"), character)
  end
end

function T:test_trailing_dots_and_spaces_are_refused()
  for _, id in ipairs({ "a.", "a ", "a..", "guide./page", "guide /page", "a. ", "page." }) do
    self:assert_not_nil(page_id.windows_problem(id), id)
  end
end

function T:test_reserved_device_names_are_refused_whatever_the_case_and_the_extension()
  local ids = { "CON", "con", "Prn", "AUX", "nul", "COM1", "com9", "LPT1", "lpt9", "CON.txt", "nul.tar.gz", "guide/aux",
    "aux/page", "Com5.v2", "CON .txt", "COM\u{B9}", "lpt\u{B2}.x" }
  for _, id in ipairs(ids) do self:assert_not_nil(page_id.windows_problem(id), id) end
  for _, id in ipairs({ "COM0", "LPT0", "CON1", "com", "lpt" }) do self:assert_nil(page_id.windows_problem(id), id) end
end

function T:test_nfc_composes_decomposed_latin_letters()
  self:assert_equal("\u{E9}", page_id.nfc("e\u{301}"))
  self:assert_equal("caf\u{E9}/\u{C5}ngstr\u{F6}m", page_id.nfc("cafe\u{301}/A\u{30A}ngstro\u{308}m"))
  self:assert_equal("\u{1EC7}", page_id.nfc("\u{1EB9}\u{302}"))
  self:assert_equal("\u{1EA5}", page_id.nfc("a\u{302}\u{301}"))
end

function T:test_nfc_leaves_composed_ascii_and_other_text_alone()
  for _, name in ipairs({ "\u{E9}", "plain", "guide/a", "\u{4E2D}\u{6587}", "\u{3B1}\u{301}", "x\u{301}", "" }) do
    self:assert_equal(name, page_id.nfc(name))
  end
  self:assert_equal("e\u{301}\xFF", page_id.nfc("e\u{301}\xFF"), "invalid UTF-8 is returned unchanged")
end

return T
