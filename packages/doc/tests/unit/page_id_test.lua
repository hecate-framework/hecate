---@diagnostic disable: need-check-nil, missing-fields  -- the tests read files they have just built; a nil fails the assertion that follows
local test = require("harness.test")
local core = require("hecate.core")
local doc = require("hecate.doc")
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
  for _, name in ipairs({ "\u{E9}", "plain", "guide/a", "\u{4E2D}\u{6587}", "x\u{301}", "" }) do
    self:assert_equal(name, page_id.nfc(name))
  end
  self:assert_equal("e\u{301}\xFF", page_id.nfc("e\u{301}\xFF"), "invalid UTF-8 is returned unchanged")
end

function T:test_console_devices_with_a_dollar_are_refused()
  for _, id in ipairs({ "CONIN$", "conout$", "Clock$", "CONIN$.txt", "a/CLOCK$" }) do
    self:assert_not_nil(page_id.windows_problem(id), id)
  end
end

function T:test_nfc_handles_names_longer_than_the_stack()
  local name = ("e\u{301}"):rep(300000)
  self:assert_equal(("\u{E9}"):rep(300000), page_id.nfc(name))
end

-- The scripts of OQ-140, closed by `hecate.unicode` (ADR 0032).
function T:test_nfc_composes_greek_cyrillic_and_hangul()
  self:assert_equal("\u{3AC}", page_id.nfc("\u{3B1}\u{301}"), "Greek with tonos")
  self:assert_equal("\u{439}", page_id.nfc("\u{438}\u{306}"), "Cyrillic short i")
  self:assert_equal("\u{43F}\u{440}\u{438}\u{432}\u{435}\u{442}/\u{451}", page_id.nfc("\u{43F}\u{440}\u{438}\u{432}\u{435}\u{442}/\u{435}\u{308}"))
  self:assert_equal("\u{AC01}", page_id.nfc("\u{1100}\u{1161}\u{11A8}"), "Hangul jamo")
  self:assert_equal("\u{D55C}\u{AE00}", page_id.nfc("\u{1112}\u{1161}\u{11AB}\u{1100}\u{1173}\u{11AF}"))
end

function T:test_nfc_handles_the_gaps_of_the_latin_table()
  self:assert_equal("\u{219}", page_id.nfc("s\u{326}"), "Romanian comma below")
  self:assert_equal("\u{C5}", page_id.nfc("\u{212B}"), "ANGSTROM SIGN")
  self:assert_equal("\u{3A9}", page_id.nfc("\u{2126}"), "OHM SIGN")
  self:assert_equal("\u{1EAD}", page_id.nfc("a\u{302}\u{323}"), "two marks, either order")
  self:assert_equal("\u{1EAD}", page_id.nfc("a\u{323}\u{302}"))
end

function T:test_nfc_reorders_several_combining_marks()
  self:assert_equal("\u{1EA1}\u{301}", page_id.nfc("a\u{301}\u{323}"), "canonical ordering, then composition")
  self:assert_equal(page_id.nfc("a\u{323}\u{301}"), page_id.nfc("a\u{301}\u{323}"))
end

-- Edge cases of the names (the page ids come from the entries of a real directory, so some of these forms are reachable
-- only through `windows_problem` itself: it is a function of any string and must answer for any string).

function T:test_a_nul_byte_is_a_control_character_in_any_position()
  for _, id in ipairs({ "\0", "a\0", "\0a", "a\0b", "dir/a\0b", "dir\0/page", "a\0\0b" }) do
    local reason = page_id.windows_problem(id)
    self:assert_not_nil(reason, ("%q"):format(id))
    self:assert_true(reason:find("control character", 1, true) ~= nil, reason)
  end
  -- The boundary of the class: U+001F is refused, U+0020 (a space inside a name) and U+007F are not reserved.
  self:assert_not_nil(page_id.windows_problem("a\31b"))
  self:assert_nil(page_id.windows_problem("a b"))
  self:assert_nil(page_id.windows_problem("a\127b"))
end

function T:test_empty_segments_are_ignored_not_refused()
  -- `a//b`, a leading and a trailing `/`: an id is file names joined by `/`, and an empty name is not one. The checks of
  -- the other segments still apply.
  for _, id in ipairs({ "a//b", "/a", "a/", "/a/", "//", "", "/" }) do self:assert_nil(page_id.windows_problem(id), ("%q"):format(id)) end
  self:assert_not_nil(page_id.windows_problem("a//b?"))
  self:assert_not_nil(page_id.windows_problem("/con"))
  self:assert_not_nil(page_id.windows_problem("a//con/"))
  self:assert_equal("a//b", page_id.nfc("a//b"))
  self:assert_equal("/a/", page_id.nfc("/a/"))
end

function T:test_dot_and_dot_dot_segments_are_refused()
  for _, id in ipairs({ ".", "..", "a/./b", "a/../b", "../a", "./a", "a/..", "a/." }) do
    local reason = page_id.windows_problem(id)
    self:assert_not_nil(reason, id)
    self:assert_true(reason:find("dot or a space", 1, true) ~= nil, reason)
  end
  self:assert_nil(page_id.windows_problem(".x"), "a name that starts with a dot is a name")
  self:assert_nil(page_id.windows_problem("a.b.c"))
  self:assert_nil(page_id.windows_problem("..a"))
end

function T:test_device_names_with_a_colon_or_a_trailing_space_are_refused()
  for _, id in ipairs({ "COM1:", "com1:x", "CON:", "NUL:", "a/COM1:", "CONIN$ ", "CONIN$ .txt", "CONOUT$  ", "CLOCK$ ", "CON ", "con .md",
    "LPT1 ", "AUX  .tar.gz" }) do
    self:assert_not_nil(page_id.windows_problem(id), ("%q"):format(id))
  end
  -- Not devices: a name that merely starts with one, or holds a space inside.
  for _, id in ipairs({ "CONIN", "CONIN$x", "COM1x", "CON X", "xCON" }) do self:assert_nil(page_id.windows_problem(id), id) end
end

function T:test_the_length_of_a_name_or_of_a_path_is_not_checked_here()
  -- The limits of the file systems (255 bytes a name, 260 characters a path on Windows without long paths) are not a
  -- naming rule of `windows_problem`: a name of 255 bytes and a path of more than 260 characters are accepted by it.
  local longest = ("a"):rep(255)
  self:assert_nil(page_id.windows_problem(longest))
  self:assert_nil(page_id.windows_problem(("a"):rep(100) .. "/" .. ("b"):rep(100) .. "/" .. ("c"):rep(100) .. "/page"))
  self:assert_equal(longest, page_id.nfc(longest))
  self:assert_equal(("\u{E9}"):rep(127), page_id.nfc(("e\u{301}"):rep(127)), "the normalised name is a name of 254 bytes")
end

function T:test_a_name_that_is_not_well_formed_utf8_is_refused_with_its_bytes_shown()
  -- A lone surrogate, overlong forms, a truncated sequence, a continuation byte alone, a byte that is never valid: a name
  -- of Linux only, which macOS and Windows cannot create.
  for _, id in ipairs({ "caf\xED\xA0\x80", "a\xC0\xAFb", "\xE0\x80\xAF", "\xF0\x80\x80\xAF", "x\xC3", "\x80", "\xFF", "dir/\xED\xB0\x80/page",
    "e\u{301}\xFF" }) do
    local reason = page_id.windows_problem(id)
    self:assert_not_nil(reason, ("%q"):format(id))
    self:assert_true(reason:find("UTF-8", 1, true) ~= nil, reason)
    self:assert_equal(id, page_id.nfc(id), "nfc leaves an unreadable name as it is: the caller refuses it")
  end
  -- Well-formed names are not touched by the rule: the extremes of UTF-8.
  for _, id in ipairs({ "\u{7F}", "\u{80}", "\u{7FF}", "\u{800}", "\u{FFFF}", "\u{10000}", "\u{10FFFF}", "\u{D7FF}", "\u{E000}" }) do
    self:assert_nil(page_id.windows_problem(id), ("U+%04X"):format(utf8.codepoint(id)))
  end
end

local function build(files)
  local fs = doc.MemoryFileSystem(files)
  local report = doc.build({ site_configuration = { title = "T", locales = { { code = "en", label = "English" }, { code = "fr", label = "Fran\u{E7}ais" } } },
    guides_dir = "c", output_dir = "o", file_system = fs })
  return fs, report
end

local function page(title) return ("---\ntitle: %s\n---\nbody\n"):format(title) end

function T:test_a_directory_with_a_reserved_name_is_refused_when_the_tree_is_scanned()
  for _, directory in ipairs({ "con", "CON", "aux", "Nul", "com1", "lpt9", "con.d", "a./b", "a /b", "what?", "a:b", "CONIN$ " }) do
    local err = self:assert_error(function()
      build({ ["c/en/index.md"] = page("Home"), ["c/en/" .. directory .. "/index.md"] = page("D"), ["c/fr/index.md"] = page("Accueil") })
    end, nil)
    self:assert_true(core.is_instance_of(err, doc.BuildError), directory .. ": " .. tostring(err))
    self:assert_true(err.message:find("not portable", 1, true) ~= nil, directory .. ": " .. err.message)
    self:assert_true(err.context.path:find("c/en/", 1, true) == 1, directory .. ": the path names the entry")
  end
  -- A nested directory, and a directory that holds nothing but a page of a translation.
  self:assert_error(function() build({ ["c/en/index.md"] = page("Home"), ["c/en/guide/con/deep/page.md"] = page("D") }) end)
  self:assert_error(function() build({ ["c/en/index.md"] = page("Home"), ["c/fr/prn/page.md"] = page("D") }) end)
end

function T:test_a_file_name_with_a_nul_byte_or_invalid_utf8_is_refused_when_the_tree_is_scanned()
  for _, name in ipairs({ "a\0b", "caf\xED\xA0\x80", "a\xC0\xAFb", "\xF0\x80\x80\xAF", "x\xC3", "d\xFFir/page" }) do
    local err = self:assert_error(function()
      build({ ["c/en/index.md"] = page("Home"), ["c/en/" .. name .. ".md"] = page("X") })
    end)
    self:assert_true(core.is_instance_of(err, doc.BuildError), ("%q: %s"):format(name, tostring(err)))
    self:assert_true(err.message:find("not portable", 1, true) ~= nil, err.message)
  end
end

function T:test_names_at_the_limits_of_length_are_built()
  local longest = ("a"):rep(252) -- 255 bytes with `.md`
  local fs = build({ ["c/en/index.md"] = page("Home"), ["c/en/" .. longest .. ".md"] = page("Long") })
  self:assert_not_nil(fs:read("o/en/" .. longest .. "/index.html"))
  local deep = ("a"):rep(100) .. "/" .. ("b"):rep(100) .. "/" .. ("c"):rep(60) .. "/page"
  self:assert_true(#deep + #"o/en//index.html" > 260)
  local fs_two = build({ ["c/en/index.md"] = page("Home"), ["c/en/" .. deep .. ".md"] = page("Deep") })
  self:assert_not_nil(fs_two:read("o/en/" .. deep .. "/index.html"))
end

function T:test_only_the_directory_differing_in_normalisation_is_one_page_across_locales_and_one_output_directory()
  -- `en` is composed, `fr` decomposed, in the directory only: one page id, so the French file is the translation (no
  -- fallback notice) and the output has one directory, in composed form.
  local fs, report = build({
    ["c/en/index.md"] = page("Home"), ["c/en/caf\u{E9}/menu.md"] = page("Menu"),
    ["c/fr/index.md"] = page("Accueil"), ["c/fr/cafe\u{301}/menu.md"] = page("Carte"),
  })
  self:assert_equal(0, #report.problems, table.concat(report.problems, "\n"))
  self:assert_equal(0, report.locales.fr.fallbacks, "the decomposed directory is the translation of the composed one")
  self:assert_not_nil(fs:read("o/fr/caf\u{E9}/menu/index.html"))
  self:assert_nil(fs.files["o/fr/cafe\u{301}/menu/index.html"], "no decomposed directory in the output")
  self:assert_true(fs:read("o/fr/caf\u{E9}/menu/index.html"):find("Carte", 1, true) ~= nil)
  -- Decomposed in the only locale that has the page: the output directory is still in composed form.
  local alone = build({ ["c/en/index.md"] = page("Home"), ["c/en/cafe\u{301}/menu.md"] = page("Menu"), ["c/fr/index.md"] = page("Accueil") })
  self:assert_not_nil(alone:read("o/en/caf\u{E9}/menu/index.html"))
  self:assert_nil(alone.files["o/en/cafe\u{301}/menu/index.html"])
  -- Two spellings of one directory in one locale, with a different file each: two pages, one output directory.
  local both = build({ ["c/en/index.md"] = page("Home"), ["c/en/caf\u{E9}/a.md"] = page("A"), ["c/en/cafe\u{301}/b.md"] = page("B"),
    ["c/fr/index.md"] = page("Accueil") })
  self:assert_not_nil(both:read("o/en/caf\u{E9}/a/index.html"))
  self:assert_not_nil(both:read("o/en/caf\u{E9}/b/index.html"))
  self:assert_nil(both.files["o/en/cafe\u{301}/b/index.html"])
end

return T
