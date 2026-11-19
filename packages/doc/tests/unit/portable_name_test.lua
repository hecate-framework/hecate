---@diagnostic disable: need-check-nil  -- tests read results they have just checked
-- `portable_name`: the one check applied to page ids, the files next to the guides, the files of `public/` and the
-- files the site configuration names; the case folding behind its key; the namespace of output paths.
local test = require("harness.test")
local portable = require("hecate.doc.internal.portable_name")
local case_fold = require("hecate.doc.internal.case_fold")
local T = test.Case("PortableNameTest")

-- Names --------------------------------------------------------------------------------------------------------------

function T:test_ordinary_names_are_portable()
  for _, path in ipairs({ "index", "img/a.svg", "guide/concurrency", "logo.svg", "r\u{E9}f\u{E9}rence/\u{416}.png", "a b/c-d_e.f" }) do
    local checked = portable.portable_name(path)
    self:assert_nil(checked.problem, path)
    self:assert_equal(0, #checked.limits, path)
  end
end

function T:test_the_windows_rules_apply_to_every_segment()
  for _, path in ipairs({ "aux.png", "img/con.svg", "con/x.svg", "x.", "dir./x", "a:b", "a?b.png", "NUL", "COM1.txt", "a/lpt9" }) do
    self:assert_not_nil(portable.portable_name(path).problem, path)
  end
end

function T:test_the_name_is_in_nfc_and_the_key_ignores_normalisation_and_case()
  local checked = portable.portable_name("img/e\u{301}.svg")
  self:assert_equal("img/\u{E9}.svg", checked.name)
  self:assert_equal(portable.portable_name("IMG/\u{C9}.SVG").key, checked.key)
  self:assert_equal(portable.portable_name("img/\u{E9}.svg").key, checked.key)
end

function T:test_the_key_tells_names_that_differ_only_by_case()
  self:assert_equal(portable.portable_name("Img/a.svg").key, portable.portable_name("img/a.svg").key)
  self:assert_equal(portable.portable_name("Logo.svg").key, portable.portable_name("logo.svg").key)
  self:assert_true(portable.portable_name("img/a.svg").key ~= portable.portable_name("img/b.svg").key)
end

function T:test_a_segment_over_255_bytes_is_a_limit_not_a_refusal()
  local at_limit = portable.portable_name(("a"):rep(255) .. ".svg")
  self:assert_equal(1, #at_limit.limits, "259 bytes with the extension")
  self:assert_equal(0, #portable.portable_name(("a"):rep(251) .. ".svg").limits, "255 bytes")
  self:assert_equal(1, #portable.portable_name("ok/" .. ("a"):rep(256)).limits)
  -- the limit is in bytes: 128 two-byte letters are 256 bytes
  self:assert_equal(1, #portable.portable_name(("\u{E9}"):rep(128)).limits)
  self:assert_equal(0, #portable.portable_name(("\u{E9}"):rep(127)).limits)
  self:assert_nil(portable.portable_name(("a"):rep(300)).problem)
end

function T:test_the_limit_message_names_the_length_and_does_not_repeat_a_long_name()
  local message = portable.portable_name(("a"):rep(300)).limits[1]
  self:assert_not_nil(message:find("300 bytes", 1, true), message)
  self:assert_not_nil(message:find("255", 1, true), message)
  self:assert_true(#message < 200, message)
end

function T:test_the_length_of_a_path_is_counted_in_utf16_units()
  self:assert_equal(3, portable.length("abc"))
  self:assert_equal(2, portable.length("\u{E9}\u{E9}"))
  self:assert_equal(2, portable.length("\u{1F600}"))
  self:assert_equal(2, portable.length("\xFF\xFE"), "not UTF-8: bytes")
end

function T:test_an_output_path_of_260_characters_or_more_is_a_problem()
  self:assert_nil(portable.path_limit_problem(("a"):rep(259)))
  local problem = portable.path_limit_problem(("a"):rep(260))
  self:assert_not_nil(problem)
  self:assert_not_nil(problem:find("260 characters", 1, true), problem)
end

function T:test_markdown_files_are_recognised_whatever_the_case_of_the_suffix()
  for _, name in ipairs({ "a.md", "A.MD", "Readme.Md", "x.mD" }) do self:assert_true(portable.is_markdown(name), name) end
  for _, name in ipairs({ ".md", "a.mdx", "md", "a.m", "amd" }) do self:assert_false(portable.is_markdown(name), name) end
end

-- Case folding -------------------------------------------------------------------------------------------------------

local function folds(a, b) return case_fold.fold(a) == case_fold.fold(b) end

function T:test_latin_greek_cyrillic_and_armenian_fold_by_case()
  self:assert_true(folds("ABC", "abc"))
  self:assert_true(folds("\u{C0}\u{D6}\u{D8}\u{DE}", "\u{E0}\u{F6}\u{F8}\u{FE}"), "Latin-1")
  self:assert_true(folds("\u{100}\u{178}\u{179}", "\u{101}\u{FF}\u{17A}"), "Latin Extended-A")
  self:assert_true(folds("\u{218}\u{21A}", "\u{219}\u{21B}"), "Romanian S and T with comma below")
  self:assert_true(folds("\u{1EA0}\u{1EBE}", "\u{1EA1}\u{1EBF}"), "Vietnamese")
  self:assert_true(folds("\u{416}.md", "\u{436}.md"), "Cyrillic ZHE")
  self:assert_true(folds("\u{400}\u{40F}\u{410}\u{42F}", "\u{450}\u{45F}\u{430}\u{44F}"), "Cyrillic")
  self:assert_true(folds("\u{386}", "\u{3AC}"), "Greek tonos")
  self:assert_true(folds("\u{391}\u{3A9}\u{38E}", "\u{3B1}\u{3C9}\u{3CD}"), "Greek")
  self:assert_true(folds("\u{531}", "\u{561}"), "Armenian")
  self:assert_true(folds("\u{FF21}", "\u{FF41}"), "fullwidth")
end

function T:test_the_singletons_fold_to_their_letters()
  self:assert_true(folds("\u{B5}", "\u{3BC}"), "micro sign and mu")
  self:assert_true(folds("\u{17F}", "s"), "long s")
  self:assert_true(folds("\u{3C2}", "\u{3C3}"), "final sigma")
  self:assert_true(folds("\u{212A}", "k"), "Kelvin")
  self:assert_true(folds("\u{2126}", "\u{3C9}"), "Ohm")
  self:assert_true(folds("\u{212B}", "\u{E5}"), "Angstrom")
  self:assert_true(folds("\u{1E9E}", "\u{DF}"), "capital sharp s folds to sharp s (simple folding)")
end

function T:test_the_multiplication_sign_and_uncased_letters_are_kept()
  self:assert_equal("\u{D7}", case_fold.fold("\u{D7}"))
  self:assert_equal("\u{DF}", case_fold.fold("\u{DF}"), "the simple folding does not expand to ss")
  self:assert_equal("\u{4E2D}\u{6587}", case_fold.fold("\u{4E2D}\u{6587}"))
  self:assert_equal("a/b.c-d_e 1", case_fold.fold("A/B.C-D_E 1"))
end

function T:test_a_name_that_is_not_utf8_is_folded_for_ascii_letters_only()
  self:assert_equal("ab\xFF", case_fold.fold("AB\xFF"))
end

function T:test_every_range_folds_to_a_different_code_point_and_ranges_do_not_overlap()
  local seen = {}
  for _, range in ipairs(case_fold.ranges()) do
    for code = range[1], range[2], range[4] do
      self:assert_true(range[3] ~= 0, "offset")
      self:assert_nil(seen[code], ("U+%04X is in two ranges"):format(code))
      seen[code] = true
    end
  end
end

function T:test_a_folded_letter_folds_to_itself()
  for _, range in ipairs(case_fold.ranges()) do
    for code = range[1], range[2], range[4] do
      local folded = utf8.char(code + range[3])
      self:assert_equal(folded, case_fold.fold(folded), ("U+%04X"):format(code + range[3]))
    end
  end
end

-- Namespace ----------------------------------------------------------------------------------------------------------

function T:test_a_namespace_accepts_distinct_paths()
  local namespace = portable.namespace()
  self:assert_nil(namespace:claim("en/a/index.html", "a.md"))
  self:assert_nil(namespace:claim("en/a/pic.svg", "pic"))
  self:assert_nil(namespace:claim("en/Img/x.svg", "x"), "directories that differ only by case do not clash")
  self:assert_nil(namespace:claim("en/img/y.svg", "y"))
end

function T:test_a_namespace_reports_the_same_path_and_the_same_key()
  local namespace = portable.namespace()
  self:assert_nil(namespace:claim("en/Img/a.svg", "first", "file"))
  local kind, other = namespace:claim("en/Img/a.svg", "second")
  self:assert_equal("same", kind)
  self:assert_equal("first", other.label)
  self:assert_equal("file", other.kind)
  kind, other = namespace:claim("en/img/a.svg", "third")
  self:assert_equal("case", kind)
  self:assert_equal("en/Img/a.svg", other.path)
  kind = namespace:claim("en/\u{418}mg/\u{416}.svg", "cyrillic")
  self:assert_nil(kind)
  self:assert_equal("case", (namespace:claim("en/\u{438}mg/\u{436}.svg", "cyrillic lower")))
end

function T:test_a_namespace_reports_a_file_and_a_directory_of_one_name()
  local namespace = portable.namespace()
  self:assert_nil(namespace:claim("en/a/index.html", "page a"))
  local kind, other = namespace:claim("en/a", "file a")
  self:assert_equal("directory", kind)
  self:assert_equal("page a", other.label)
  local second = portable.namespace()
  self:assert_nil(second:claim("en/A", "file A"))
  kind, other = second:claim("en/a/b.html", "page")
  self:assert_equal("directory", kind)
  self:assert_equal("file A", other.label)
  self:assert_nil(second:claim("en/other", "unrelated"), "a refused path is not recorded")
  self:assert_equal("directory", (second:claim("en/a/b.html", "again")))
end

return T
