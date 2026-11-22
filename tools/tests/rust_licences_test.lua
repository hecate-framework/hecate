local test = require("harness.test")
local rust = require("lib.rust_licences")
local sha256 = require("lib.sha256")
local T = test.Case("RustLicencesTest")

local TREE = table.concat({
  "hecate-doc-native v0.0.0 (/home/u/hecate/packages/doc/native)|MIT",
  "comrak v0.59.0|BSD-2-Clause",
  "serde v1.0.229|MIT OR Apache-2.0",
  "serde v1.0.229|MIT OR Apache-2.0 (*)",
  "serde_derive v1.0.229 (proc-macro)|MIT OR Apache-2.0",
  "two-face v0.5.2+bat-0.26.1|MIT OR Apache-2.0",
}, "\n")

function T:test_parse_tree_lists_each_crate_once_and_skips_the_root()
  local crates = assert(rust.parse_tree(TREE))
  self:assert_equal(4, #crates)
  self:assert_equal("comrak", crates[1].name)
  self:assert_equal("0.59.0", crates[1].version)
  self:assert_equal("BSD-2-Clause", crates[1].license)
  self:assert_equal("serde", crates[2].name)
  self:assert_equal("serde_derive", crates[3].name)
  self:assert_true(crates[3].proc_macro)
  self:assert_equal("0.5.2+bat-0.26.1", crates[4].version)
end

function T:test_parse_tree_reports_a_line_it_does_not_understand()
  local crates, problem = rust.parse_tree("garbage")
  self:assert_nil(crates)
  self:assert_true(assert(problem):find("garbage", 1, true) ~= nil)
end

function T:test_parse_tree_reports_a_crate_without_licence_expression()
  local crates = assert(rust.parse_tree("a v1.0.0|\nb v1.0.0|MIT"))
  self:assert_equal("", crates[1].license)
end

function T:test_expression_relies_on_the_first_permissive_alternative()
  self:assert_equal("MIT", table.concat(assert(rust.parse_expression("MIT OR Apache-2.0")), ","))
  self:assert_equal("Apache-2.0", table.concat(assert(rust.parse_expression("Apache-2.0 OR MIT")), ","))
  self:assert_equal("Apache-2.0", table.concat(assert(rust.parse_expression("Apache-2.0 / MIT")), ","))
  self:assert_equal("Unlicense", table.concat(assert(rust.parse_expression("Unlicense/MIT")), ","))
  self:assert_equal("0BSD", table.concat(assert(rust.parse_expression("0BSD OR MIT OR Apache-2.0")), ","))
end

local DENY = [[
[graph]
targets = ["x86_64-unknown-linux-gnu"]

[licenses]
# comment with a "quoted" word ] and a bracket
allow = [
  "MIT",
  "Apache-2.0",   # first
  "BSD-2-Clause", # second ]
  "Unicode-3.0",
]
confidence-threshold = 0.93

[bans]
allow = ["NotALicence"]
]]

function T:test_allow_list_is_read_from_the_licenses_table_only()
  local allowed = assert(rust.parse_allow_list(DENY))
  self:assert_true(allowed["MIT"] and allowed["Apache-2.0"] and allowed["BSD-2-Clause"] and allowed["Unicode-3.0"])
  self:assert_nil(allowed["NotALicence"])
  self:assert_nil(allowed["0BSD"])
  self:assert_nil(rust.parse_allow_list("[licenses]\nconfidence-threshold = 0.9\n"))
  local one = assert(rust.parse_allow_list('[licenses]\nallow = ["MIT", "ISC"]\n'))
  self:assert_true(one["MIT"] and one["ISC"])
end

function T:test_expression_prefers_an_alternative_of_the_allow_list()
  local allowed = assert(rust.parse_allow_list(DENY))
  local function relied(expression) return table.concat(assert(rust.parse_expression(expression, allowed)), ",") end
  self:assert_equal("MIT", relied("0BSD OR MIT OR Apache-2.0"))
  self:assert_equal("MIT", relied("Zlib OR MIT"))
  self:assert_equal("MIT", relied("MIT OR Zlib OR Apache-2.0"))
  self:assert_equal("MIT", relied("Unlicense OR MIT"))
  self:assert_equal("Apache-2.0", relied("Apache-2.0 / MIT"))
  self:assert_equal("MIT,Unicode-3.0", relied("(0BSD OR MIT) AND Unicode-3.0"))
  -- No alternative in the list: the first permissive one (the audit will refuse the crate, not this page).
  self:assert_equal("0BSD", relied("0BSD OR Zlib"))
  -- Without a list, the declared order decides, as before.
  self:assert_equal("0BSD", table.concat(assert(rust.parse_expression("0BSD OR MIT")), ","))
  local none, problem = rust.parse_expression("GPL-3.0-only", allowed)
  self:assert_nil(none)
  self:assert_true(assert(problem):find("GPL-3.0-only", 1, true) ~= nil)
end

function T:test_expression_relies_on_every_term_of_an_and()
  local ids = assert(rust.parse_expression("(MIT OR Apache-2.0) AND Unicode-3.0"))
  self:assert_equal("MIT,Unicode-3.0", table.concat(ids, ","))
end

function T:test_expression_skips_a_copyleft_alternative()
  self:assert_equal("MIT", table.concat(assert(rust.parse_expression("GPL-3.0-only OR MIT")), ","))
end

function T:test_expression_without_permissive_choice_is_a_problem()
  local ids, problem = rust.parse_expression("GPL-3.0-only")
  self:assert_nil(ids)
  self:assert_true(assert(problem):find("GPL-3.0-only", 1, true) ~= nil)
  local none, empty = rust.parse_expression("")
  self:assert_nil(none)
  self:assert_true(empty ~= nil)
end

function T:test_expression_syntax_error_is_a_problem()
  local ids, problem = rust.parse_expression("MIT OR (Apache-2.0")
  self:assert_nil(ids)
  self:assert_true(problem ~= nil)
end

function T:test_licence_file_names()
  for _, name in ipairs({ "LICENSE", "LICENSE-MIT", "LICENSE-APACHE", "LICENCE.md", "COPYING", "COPYING.txt", "NOTICE",
    "UNICODE-LICENSE.txt", "LICENSE-UNICODE", "license-0BSD", "COPYRIGHT", "LICENSE.md" }) do
    self:assert_true(rust.is_licence_file(name), name)
  end
  for _, name in ipairs({ "README.md", "Cargo.toml", "CHANGELOG.md", "licensing.rs", "src", "CONTRIBUTING.md" }) do
    self:assert_false(rust.is_licence_file(name), name)
  end
end

function T:test_normalise_makes_the_text_independent_of_line_endings()
  self:assert_equal("a\nb  c\n\td\n", rust.normalise("a  \r\nb  c\r\n\td \n\n\n"))
  self:assert_equal("a\n", rust.normalise("a"))
end

local function crate(name, version, license, files, extra)
  local c = { name = name, version = version, license = license, relied = assert(rust.parse_expression(license)),
    files = files or {} }
  for k, v in pairs(extra or {}) do c[k] = v end
  return c
end

local function model(crates, extra)
  local m = { module = "hecate-x-native", directory = "packages/x/native", task = "gen-rust-licences",
    lock_sha256 = ("ab"):rep(32), crates = crates }
  for k, v in pairs(extra or {}) do m[k] = v end
  return m
end

function T:test_render_is_deterministic_and_marked()
  local m = model({
    crate("b", "2.0.0", "MIT OR Apache-2.0", { { name = "LICENSE-MIT", text = "MIT text\n" } }),
    crate("a", "1.0.0", "MIT", { { name = "LICENSE", text = "MIT text\n" } }),
  })
  local first = rust.render(m)
  self:assert_equal(first, rust.render(m))
  self:assert_true(first:find("generated by `lua tools/run.lua gen-rust-licences`", 1, true) ~= nil)
  self:assert_true(first:find(("ab"):rep(32), 1, true) ~= nil)
end

function T:test_render_groups_identical_texts_and_sorts_crates()
  local m = model({
    crate("b", "2.0.0", "MIT", { { name = "LICENSE", text = "same\n" } }),
    crate("a", "1.0.0", "MIT", { { name = "LICENSE", text = "same\n" } }),
    crate("c", "3.0.0", "MIT", { { name = "LICENSE", text = "other\n" } }),
  })
  local page = rust.render(m)
  local _, count = page:gsub("\n````text\n", "")
  self:assert_equal(2, count)
  self:assert_true(page:find("| `a` | 1.0.0", 1, true) < page:find("| `b` | 2.0.0", 1, true))
  self:assert_true(page:find("`a` 1.0.0, `b` 2.0.0", 1, true) ~= nil)
end

function T:test_render_uses_a_longer_fence_than_the_text_holds()
  local page = rust.render(model({ crate("a", "1.0.0", "MIT", { { name = "LICENSE", text = "x ```` y\n" } }) }))
  self:assert_true(page:find("\n`````text\n", 1, true) ~= nil)
end

function T:test_render_says_which_alternative_is_relied_on()
  local page = rust.render(model({ crate("a", "1.0.0", "Apache-2.0 OR MIT", { { name = "LICENSE-MIT", text = "m\n" } }) }))
  self:assert_true(page:find("| `a` | 1.0.0 | Apache-2.0 OR MIT | Apache-2.0 |", 1, true) ~= nil)
  self:assert_true(page:find("allow list of `deny.toml`", 1, true) ~= nil)
end

function T:test_render_marks_a_fallback_text()
  local m = model({ crate("a", "1.0.0", "MIT", {}, { fallback = { id = "MIT", text = "standard\n", authors = "A. B." } }) })
  local page = rust.render(m)
  self:assert_true(page:find("standard text of MIT", 1, true) ~= nil)
  self:assert_true(page:find("ships no licence file", 1, true) ~= nil)
  self:assert_true(page:find("A. B.", 1, true) ~= nil)
end

function T:test_render_lists_the_embedded_syntaxes()
  local m = model({ crate("a", "1.0.0", "MIT", { { name = "LICENSE", text = "m\n" } }) }, {
    syntaxes = { source = "two-face 0.5.2+bat-0.26.1", entries = {
      { ty = "Mit", path = "syntaxes/Z/LICENSE", text = "mit\n" },
      { ty = "Mit", path = "syntaxes/A/LICENSE", text = "mit\n" },
      { ty = "Apache2", path = "syntaxes/K/LICENSE", text = "apache\n" },
    } } })
  local page = rust.render(m)
  self:assert_true(page:find("Embedded syntax definitions", 1, true) ~= nil)
  self:assert_true(page:find("`syntaxes/A/LICENSE`", 1, true) < page:find("`syntaxes/Z/LICENSE`", 1, true))
  self:assert_equal(page, rust.render(m))
end

function T:test_parse_acknowledgements()
  local text = "line one\nline two\n"
  local output = ("LICENCE Mit syntaxes\\A\\LICENSE %d\n%s\nLICENCE Apache2 b/LICENSE 2\nx\n\n"):format(#text, text)
  local entries = assert(rust.parse_acknowledgements(output))
  self:assert_equal(2, #entries)
  self:assert_equal("syntaxes/A/LICENSE", entries[1].path)
  self:assert_equal("Mit", entries[1].ty)
  self:assert_equal(text, entries[1].text)
  self:assert_equal("x\n", entries[2].text)
end

function T:test_parse_acknowledgements_rejects_a_truncated_output()
  local entries, problem = rust.parse_acknowledgements("LICENCE Mit a/LICENSE 99\nshort\n")
  self:assert_nil(entries)
  self:assert_true(problem ~= nil)
  local none = rust.parse_acknowledgements("")
  self:assert_nil(none)
end

function T:test_lock_digest_ignores_line_endings()
  local hex = function(s) return "h(" .. s .. ")" end
  self:assert_equal("h(a\nb\n)", rust.lock_digest("a\r\nb\r\n", hex))
end

function T:test_header_digest_is_read_back()
  local page = rust.render(model({ crate("a", "1.0.0", "MIT", { { name = "LICENSE", text = "m\n" } }) }))
  self:assert_equal(("ab"):rep(32), rust.recorded_digest(page))
  self:assert_nil(rust.recorded_digest("nothing"))
end

function T:test_check_page()
  local hex = function(s) return "h" .. #s end
  self:assert_nil(rust.check_page("d", nil, nil, hex))
  self:assert_true(rust.check_page("d", "abc", nil, hex):find("missing", 1, true) ~= nil)
  self:assert_true(rust.check_page("d", "abc", "Cargo.lock SHA-256: `ab12`", hex):find("does not match", 1, true) ~= nil)
  self:assert_true(rust.check_page("d", "abc", "no digest", hex):find("does not match", 1, true) ~= nil)
end

function T:test_check_page_accepts_a_page_that_records_the_real_digest_of_the_lock()
  local lock = "# Cargo.lock\nversion = 4\n"
  local page = rust.render(model({ crate("a", "1.0.0", "MIT", { { name = "LICENSE", text = "m\n" } }) },
    { lock_sha256 = sha256.hex(lock) }))
  self:assert_nil(rust.check_page("d", lock, page, sha256.hex))
  self:assert_nil(rust.check_page("d", (lock:gsub("\n", "\r\n")), page, sha256.hex), "a CRLF checkout of the lock gives the same digest")
  local changed = rust.check_page("d", lock .. "# edited\n", page, sha256.hex)
  self:assert_true(assert(changed):find("does not match", 1, true) ~= nil)
  self:assert_equal(sha256.hex("a\nb\n"), rust.lock_digest("a\r\nb\r\n", sha256.hex))
end

function T:test_expression_with_unbalanced_or_repeated_tokens_is_a_problem()
  for _, expression in ipairs({ "MIT )", "MIT MIT", "()", "(", ")", "MIT OR", "OR MIT", "AND", "MIT AND", "MIT OR OR ISC",
    "MIT WITH", "WITH MIT", "( )", "MIT (Apache-2.0)", "MIT or Apache-2.0", "MIT and ISC", "MIT Or ISC" }) do
    local ids, problem = rust.parse_expression(expression)
    self:assert_nil(ids, expression)
    self:assert_not_nil(problem, expression)
  end
  local _, trailing = rust.parse_expression("MIT )")
  self:assert_true(assert(trailing):find("trailing ')'", 1, true) ~= nil, trailing)
  local _, twice = rust.parse_expression("MIT MIT")
  self:assert_true(assert(twice):find("trailing 'MIT'", 1, true) ~= nil, twice)
  local _, lower = rust.parse_expression("MIT or Apache-2.0")
  self:assert_true(assert(lower):find("'or'", 1, true) ~= nil, "the operators are upper case, as SPDX writes them: " .. lower)
end

function T:test_expression_keeps_the_exception_of_a_with()
  local ids = assert(rust.parse_expression("Apache-2.0 WITH LLVM-exception"))
  self:assert_equal(1, #ids)
  self:assert_equal("Apache-2.0 WITH LLVM-exception", ids[1])
  local both = assert(rust.parse_expression("(Apache-2.0 WITH LLVM-exception) OR MIT"))
  self:assert_equal("Apache-2.0 WITH LLVM-exception", both[1])
  local copyleft = rust.parse_expression("GPL-2.0-only WITH Classpath-exception-2.0")
  self:assert_nil(copyleft, "an exception does not make a copyleft licence permissive")
end

function T:test_expression_binds_and_tighter_than_or()
  self:assert_equal("MIT,Apache-2.0", table.concat(assert(rust.parse_expression("MIT AND Apache-2.0 OR ISC")), ","))
  self:assert_equal("ISC", table.concat(assert(rust.parse_expression("ISC OR MIT AND Apache-2.0")), ","))
  self:assert_equal("ISC", table.concat(assert(rust.parse_expression("GPL-3.0-only AND MIT OR ISC")), ","))
  self:assert_equal("MIT,Apache-2.0,ISC", table.concat(assert(rust.parse_expression("MIT AND (Apache-2.0 OR GPL-3.0-only) AND ISC")), ","))
  local none, problem = rust.parse_expression("GPL-3.0-only AND MIT")
  self:assert_nil(none, "an AND needs every term")
  self:assert_true(assert(problem):find("GPL-3.0-only", 1, true) ~= nil)
end

function T:test_parse_tree_skips_a_path_crate_of_a_windows_checkout_and_keeps_a_git_crate()
  local crates = assert(rust.parse_tree(table.concat({
    "hecate-x-native v0.0.0 (C:\\Users\\u\\hecate\\packages\\x\\native)|MIT",
    "hecate-y v0.0.0 (D:/a/hecate/hecate/packages/y/native)|MIT",
    "local-dep v0.1.0 (/home/u/hecate/packages/z)|MIT",
    "forked v1.2.3 (https://github.com/example/forked?rev=abc123#abc123de)|MIT OR Apache-2.0",
    "other v2.0.0 (ssh://git@example.com/o.git#abcdef12)|Apache-2.0",
    "plain v1.0.0|ISC",
  }, "\r\n")))
  local names = {}
  for _, c in ipairs(crates) do names[#names + 1] = c.name end
  self:assert_equal("forked,other,plain", table.concat(names, ","), "path crates are the workspace, git crates are dependencies")
end

function T:test_fallback_text_exists_for_mit_only()
  self:assert_true(rust.fallback_text("MIT"):find("Permission is hereby granted", 1, true) ~= nil)
  self:assert_nil(rust.fallback_text("Apache-2.0"))
end

function T:test_read_authors()
  local manifest = 'name = "x"\nauthors = ["A. B. <a@b.c>", "D E"]\nlicense = "MIT"\n'
  self:assert_equal("A. B. <a@b.c>, D E", rust.read_authors(manifest))
  self:assert_nil(rust.read_authors('name = "x"\n'))
end

return T
