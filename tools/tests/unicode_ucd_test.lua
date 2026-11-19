local test = require("harness.test")
local ucd = require("lib.unicode_ucd")
local util = require("lib.util")
local T = test.Case("UnicodeUcdTest")

-- A few real lines of UnicodeData.txt: a letter, two marks, a decomposable letter and a letter that decomposes in
-- two steps, a singleton (OHM SIGN), a compatibility mapping, a non-starter decomposition and a Hangul range.
local UNICODE_DATA = table.concat({
  "0041;LATIN CAPITAL LETTER A;Lu;0;L;;;;;N;;;;0061;",
  "0300;COMBINING GRAVE ACCENT;Mn;230;NSM;;;;;N;NON-SPACING GRAVE;;;;",
  "0301;COMBINING ACUTE ACCENT;Mn;230;NSM;;;;;N;NON-SPACING ACUTE;;;;",
  "0304;COMBINING MACRON;Mn;230;NSM;;;;;N;NON-SPACING MACRON;;;;",
  "0323;COMBINING DOT BELOW;Mn;220;NSM;;;;;N;NON-SPACING DOT BELOW;;;;",
  "00C0;LATIN CAPITAL LETTER A WITH GRAVE;Lu;0;L;0041 0300;;;;N;LATIN CAPITAL LETTER A GRAVE;;;00E0;",
  "1EA0;LATIN CAPITAL LETTER A WITH DOT BELOW;Lu;0;L;0041 0323;;;;N;;;;1EA1;",
  "1EAC;LATIN CAPITAL LETTER A WITH CIRCUMFLEX AND DOT BELOW;Lu;0;L;1EA0 0302;;;;N;;;;1EAD;",
  "0340;COMBINING GRAVE TONE MARK;Mn;230;NSM;0300;;;;N;NON-SPACING GRAVE TONE MARK;;;;",
  "0344;COMBINING GREEK DIALYTIKA TONOS;Mn;230;NSM;0308 0301;;;;N;GREEK NON-SPACING DIAERESIS TONOS;;;;",
  "2126;OHM SIGN;Lu;0;L;03A9;;;;N;OHM;;;03C9;",
  "00A0;NO-BREAK SPACE;Zs;0;CS;<noBreak> 0020;;;;N;NON-BREAKING SPACE;;;;",
  "0302;COMBINING CIRCUMFLEX ACCENT;Mn;230;NSM;;;;;N;NON-SPACING CIRCUMFLEX;;;;",
  "0308;COMBINING DIAERESIS;Mn;230;NSM;;;;;N;NON-SPACING DIAERESIS;;;;",
  "AC00;<Hangul Syllable, First>;Lo;0;L;;;;;N;;;;;",
  "D7A3;<Hangul Syllable, Last>;Lo;0;L;;;;;N;;;;;",
}, "\n") .. "\n"

local PROPERTIES = table.concat({
  "# comment",
  "0340..0341    ; Full_Composition_Exclusion # Mn   [2] COMBINING GRAVE TONE MARK..COMBINING ACUTE TONE MARK",
  "0344          ; Full_Composition_Exclusion # Mn       COMBINING GREEK DIALYTIKA TONOS",
  "2126          ; Full_Composition_Exclusion # L&       OHM SIGN",
  "0958          ; FC_NFKC; 0915 093C # something else",
}, "\n") .. "\n"

function T:test_the_version_of_a_url()
  self:assert_equal("18.0.0", ucd.version_of_url("https://www.unicode.org/Public/18.0.0/ucd/UnicodeData.txt"))
  self:assert_nil(ucd.version_of_url("https://www.unicode.org/Public/UCD/latest/ucd/UnicodeData.txt"))
end

function T:test_unicode_data_gives_classes_and_canonical_mappings_only()
  local parsed = ucd.parse_unicode_data(UNICODE_DATA)
  self:assert_equal(230, parsed.combining[0x300])
  self:assert_equal(220, parsed.combining[0x323])
  self:assert_nil(parsed.combining[0x41])
  self:assert_equal(2, #parsed.mappings[0xC0])
  self:assert_equal(1, #parsed.mappings[0x2126])
  self:assert_nil(parsed.mappings[0xA0], "a compatibility mapping is not canonical")
  self:assert_nil(parsed.mappings[0xAC00], "Hangul syllables are algorithmic")
  self:assert_error(function() ucd.parse_unicode_data("zzzz;x\n") end, "malformed")
end

function T:test_the_exclusions_are_read_from_ranges_and_single_code_points_of_one_property()
  local set = ucd.parse_exclusions(PROPERTIES)
  self:assert_true(set[0x340] and set[0x341] and set[0x344] and set[0x2126])
  self:assert_nil(set[0x958])
  self:assert_nil(set[0x342])
end

function T:test_the_model()
  local model = ucd.build(UNICODE_DATA, PROPERTIES)
  -- 0300..0301 and 0302, 0304, 0308, 0340, 0344 are all 230 but not adjacent in the file: 0300..0302 merge.
  self:assert_equal(0x300, model.combining[1])
  self:assert_equal(0x302, model.combining[2])
  self:assert_equal(230, model.combining[3])
  self:assert_equal(0x304, model.combining[4])
  self:assert_equal(0x304, model.combining[5])
  -- Full decomposition expands in one step what is defined in two.
  self:assert_equal(3, #model.decomposition[0x1EAC])
  self:assert_equal(0x41, model.decomposition[0x1EAC][1])
  self:assert_equal(0x323, model.decomposition[0x1EAC][2])
  self:assert_equal(0x302, model.decomposition[0x1EAC][3])
  self:assert_equal(0x3A9, model.decomposition[0x2126][1])
  -- Primary composites: the singleton and the excluded non-starter decompositions are not composed.
  self:assert_equal(0xC0, model.composition[0x41][0x300])
  self:assert_equal(0x1EA0, model.composition[0x41][0x323])
  self:assert_equal(0x1EAC, model.composition[0x1EA0][0x302])
  self:assert_nil(model.composition[0x3A9])
  self:assert_nil(model.composition[0x308] and model.composition[0x308][0x301])
end

function T:test_the_rendering_is_deterministic_and_carries_the_notice()
  local meta = { version = "18.0.0", files = { "UnicodeData.txt", "DerivedNormalizationProps.txt" } }
  local first = ucd.render(ucd.build(UNICODE_DATA, PROPERTIES), meta)
  local second = ucd.render(ucd.build(UNICODE_DATA, PROPERTIES), meta)
  for _, name in ipairs({ "init.lua", "combining_class.lua", "decomposition.lua", "composition.lua" }) do
    self:assert_equal(first[name], second[name], name)
    self:assert_true(first[name]:find("UNICODE LICENSE V3", 1, true) ~= nil, name .. " carries the licence")
    self:assert_true(first[name]:find("Unicode Character Database 18.0.0", 1, true) ~= nil, name .. " names the version")
    self:assert_true(first[name]:find("^%-%- GENERATED") ~= nil, name)
  end
  self:assert_true(first["init.lua"]:find('unicode_version = "18.0.0"', 1, true) ~= nil)
  self:assert_true(first["init.lua"]:find("format = 1", 1, true) ~= nil)
  self:assert_true(first["decomposition.lua"]:find("[0x1EAC] = { 0x0041, 0x0323, 0x0302 },", 1, true) ~= nil)
  self:assert_true(first["composition.lua"]:find("[0x0041] = { [0x0300] = 0x00C0, [0x0323] = 0x1EA0 },", 1, true) ~= nil)
  self:assert_true(first["combining_class.lua"]:find("0x0300, 0x0302, 230,", 1, true) ~= nil)
end

function T:test_the_latest_version_is_read_from_the_readme()
  local readme = "# Unicode Character Database\n\nThis directory contains final data files for version 18.0.0 of the\nUnicode Character Database.\n"
  self:assert_equal("18.0.0", ucd.latest_version(readme))
  self:assert_equal("18.0.0", ucd.latest_version("files for version 18.0.0 of\nthe Unicode Character Database and for the"))
  self:assert_nil(ucd.latest_version("nothing here"))
end

function T:test_versions_compare_numerically()
  self:assert_equal(0, ucd.compare_versions("18.0.0", "18.0.0"))
  self:assert_equal(1, ucd.compare_versions("18.0.0", "17.0.0"))
  self:assert_equal(-1, ucd.compare_versions("9.0.0", "10.0.0"))
  self:assert_equal(1, ucd.compare_versions("15.1.0", "15.0.1"))
  self:assert_equal(-1, ucd.compare_versions("15.0.0", "15.0.1"))
end

function T:test_a_cyclic_decomposition_mapping_is_an_error_and_not_a_hang()
  local cyclic = "0041;A;Lu;0;L;0042;;;;N;;;;;\n0042;B;Lu;0;L;0041;;;;N;;;;;\n"
  local err = self:assert_error(function() ucd.build(cyclic, PROPERTIES) end, "does not end")
  self:assert_true(tostring(err):find("U+00", 1, true) ~= nil, "the message names the code point")
  local selfref = "0041;A;Lu;0;L;0041;;;;N;;;;;\n"
  self:assert_error(function() ucd.build(selfref, PROPERTIES) end, "does not end")
end

function T:test_an_empty_or_unrelated_properties_file_is_an_error()
  self:assert_error(function() ucd.build(UNICODE_DATA, "") end, "no Full_Composition_Exclusion")
  self:assert_error(function() ucd.build(UNICODE_DATA, "# only a comment\n0958 ; FC_NFKC; 0915 093C # x\n") end,
    "no Full_Composition_Exclusion")
  self:assert_equal(0, next(ucd.parse_exclusions("")) or 0)
end

function T:test_a_range_line_with_a_combining_class_or_a_mapping_is_an_error()
  local ranged = "4E00;<CJK Ideograph, First>;Lo;0;L;;;;;N;;;;;\n9FFF;<CJK Ideograph, Last>;Lo;0;L;;;;;N;;;;;\n"
  local parsed = ucd.parse_unicode_data(ranged)
  self:assert_nil(parsed.combining[0x4E00], "a range with class 0 is accepted")
  self:assert_error(function()
    ucd.parse_unicode_data("0300;<Marks, First>;Mn;230;NSM;;;;;N;;;;;\n0301;<Marks, Last>;Mn;230;NSM;;;;;N;;;;;\n")
  end, "range line")
  self:assert_error(function()
    ucd.parse_unicode_data("0301;<Marks, Last>;Mn;230;NSM;;;;;N;;;;;\n")
  end, "range line")
  self:assert_error(function()
    ucd.parse_unicode_data("4E00;<CJK Ideograph, First>;Lo;0;L;0041;;;;N;;;;;\n")
  end, "range line")
end

function T:test_a_malformed_unicode_data_line_is_an_error()
  self:assert_error(function() ucd.parse_unicode_data("0041;A;Lu;xx;L;;;;;N;;;;;\n") end, "malformed")
  self:assert_error(function() ucd.parse_unicode_data("0041;A;Lu;0;L\n") end, "malformed")
  self:assert_error(function() ucd.parse_unicode_data("\nzz;A;Lu;0;L;;;;;N;;;;;\n") end, "malformed")
end

function T:test_a_malformed_version_is_refused()
  for _, version in ipairs({ "18.0", "18", "18.0.0.1", "v18.0.0", "18.0.x", "", "18.0.0 " }) do
    self:assert_error(function() ucd.compare_versions(version, "18.0.0") end, "not a Unicode version")
    self:assert_error(function() ucd.compare_versions("18.0.0", version) end, "not a Unicode version")
  end
  self:assert_nil(ucd.version_of_url("https://www.unicode.org/Public/18.0/ucd/UnicodeData.txt"))
  self:assert_nil(ucd.version_of_url("https://www.unicode.org/Public/18.0.0.1/ucd/UnicodeData.txt"))
  self:assert_nil(ucd.latest_version("for version 18.0 of the Unicode Character Database"))
end

local ROOT = ((debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or ".") .. "/../.."):gsub("\\", "/")

function T:set_up()
  self.dir = assert(util.make_temp_dir(ROOT .. "/.hecate/tmp", "ucd-test"))
end

function T:tear_down() util.remove_tree(self.dir) end

local function write(path, data)
  local f = assert(io.open(path, "wb"))
  f:write(data)
  f:close()
end

local function readme_text(version)
  return ("final data files for version %s of the\nUnicode Character Database.\n"):format(version)
end

function T:test_the_nightly_task_fails_on_a_newer_version_only()
  local task = require("tasks.check_unicode_version")
  local root = ROOT
  local function readme(version)
    local path = self.dir .. "/ReadMe-" .. version
    write(path, readme_text(version))
    return path
  end
  local pinned = ucd.version_of_url(assert(loadfile(root .. "/packages/unicode-data/tests/external.lua"))()[1].url)
  local same = task.run({ root = root, args = { "--readme", readme(pinned) } })
  self:assert_true(same.ok, table.concat(same.problems, "; "))
  local newer = task.run({ root = root, args = { "--readme", readme("99.0.0") } })
  self:assert_false(newer.ok)
  self:assert_equal("99.0.0", newer.data.latest)
  self:assert_true(newer.problems[1]:find("99.0.0", 1, true) ~= nil)
  self:assert_true(task.run({ root = root, args = { "--readme", readme("1.0.0") } }).ok, "an older latest is not a failure")
  self:assert_false(task.run({ root = root, args = { "--bogus" } }).ok)
  self:assert_false(task.run({ root = root, args = { "--readme", self.dir .. "/absent" } }).ok)
end

local function scratch_directories()
  local found = {}
  for _, name in ipairs(util.list_dir(ROOT .. "/.hecate/tmp")) do
    if name:find("^unicode%-version%-") then found[#found + 1] = name end
  end
  return found
end

function T:test_the_online_check_downloads_a_small_https_file_into_a_directory_it_removes()
  local task = require("tasks.check_unicode_version")
  local before = #scratch_directories()
  local call
  local function download(url, path, max)
    call = { url = url, path = path, max = max }
    write(path, readme_text("1.0.0"))
    return "", true
  end
  local report = task.run({ root = ROOT, args = {}, download = download })
  self:assert_true(report.ok, table.concat(report.problems, "; "))
  self:assert_equal("https://www.unicode.org/Public/UCD/latest/ReadMe.txt", call.url)
  self:assert_equal(1048576, call.max, "at most 1 MiB")
  self:assert_true(call.path:find("/.hecate/tmp/unicode-version-", 1, true) ~= nil, call.path)
  self:assert_nil(call.path:find("^/tmp/"), "not the system temporary directory")
  self:assert_equal(before, #scratch_directories(), "the scratch directory is removed")
  self:assert_false(util.exists(call.path))
end

function T:test_the_online_check_fails_on_a_failed_empty_or_oversized_download()
  local task = require("tasks.check_unicode_version")
  local before = #scratch_directories()
  local failed = task.run({ root = ROOT, args = {}, download = function() return "boom", false end })
  self:assert_false(failed.ok)
  self:assert_true(failed.problems[1]:find("boom", 1, true) ~= nil)
  local empty = task.run({ root = ROOT, args = {}, download = function(_, path) write(path, "") return "", true end })
  self:assert_false(empty.ok)
  local big = task.run({ root = ROOT, args = {}, download = function(_, path, max)
    write(path, readme_text("1.0.0") .. ("x"):rep(max))
    return "", true
  end })
  self:assert_false(big.ok)
  self:assert_true(big.problems[1]:find("larger", 1, true) ~= nil, big.problems[1])
  self:assert_equal(before, #scratch_directories(), "every failure removes the scratch directory")
end

return T
