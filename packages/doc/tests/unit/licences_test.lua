---@diagnostic disable: need-check-nil, undefined-field  -- tests index results that a failing assertion would reveal
-- The third-party licences page: the rocks of an installed tree (rockspecs read as data, never run) and what the
-- generated site bundles, with the licence texts (documentation.md, "Documentation of a project").
local test = require("harness.test")
local doc = require("hecate.doc")
local licences = require("hecate.doc.licences")
local project = require("hecate.doc.project")
local theme = require("hecate.doc.theme")
local T = test.Case("LicensesTest")

local function has(text, part) return text:find(part, 1, true) ~= nil end

local TREE = "tree/lib/luarocks/rocks-5.5"

local function rockspec(name, version, licence, dependencies)
  local deps = {}
  for _, dependency in ipairs(dependencies or {}) do deps[#deps + 1] = ("%q"):format(dependency) end
  return ([[
rockspec_format = "3.0"
package = %q
version = %q
source = { url = "git+https://example.org/%s.git" }
description = { summary = "The %s rock.", license = %q, homepage = "https://example.org/%s" }
dependencies = { "lua >= 5.4", %s }
build = { type = "builtin", modules = {} }
]]):format(name, version, name, name, licence, name, table.concat(deps, ", "))
end

local function add_rock(files, name, version, licence, dependencies, extra)
  local directory = ("%s/%s/%s"):format(TREE, name, version)
  files[("%s/%s-%s.rockspec"):format(directory, name, version)] = rockspec(name, version, licence, dependencies)
  for path, text in pairs(extra or {}) do files[directory .. "/" .. path] = text end
end

local function tree_options(extra)
  local options = { rocks_tree_dir = "tree" }
  for key, value in pairs(extra or {}) do options[key] = value end
  return options
end

function T:test_parse_rockspec_reads_the_data_of_the_rock()
  local rock = licences.parse_rockspec(rockspec("luv", "1.53.0-1", "Apache-2.0", { "other >= 1.0, < 2" }))
  self:assert_equal("luv", rock.name)
  self:assert_equal("1.53.0-1", rock.version)
  self:assert_equal("Apache-2.0", rock.licence)
  self:assert_equal("other", table.concat(rock.dependencies, ","))
end

function T:test_parse_rockspec_refuses_anything_that_calls()
  local hostile = {
    'package = "a"\nversion = "1-1"\nos.execute("touch /tmp/hecate-probe")',
    'package = "a"\nversion = "1-1"\nx = ("x"):rep(1e10)',
    'package = "a"\nversion = "1-1"\nwhile true do end',
    'package = "a"\nversion = "1-1"\nx = load("return 1")()',
    'package = "a"\nversion = "1-1"\nfor i = 1, 1e12 do end',
    'package = "a"\nversion = "1-1"\ngoto done\n::done::',
    'package = "a"\nversion = "1-1"\n_G.hecate_licences_probe = true',
  }
  for _, text in ipairs(hostile) do
    local rock, problem = licences.parse_rockspec(text)
    self:assert_nil(rock, text)
    self:assert_not_nil(problem, text)
  end
  self:assert_nil(rawget(_G, "hecate_licences_probe"))
end

function T:test_parse_rockspec_ignores_calls_in_strings_and_comments()
  local rock = licences.parse_rockspec('-- run os.execute("x") here\n--[==[ f() ]==]\npackage = "a" -- (note)\n'
    .. 'version = "1-1"\ndescription = { license = [[MIT (modified): see f()]] }\n')
  self:assert_equal("a", rock.name)
  self:assert_equal("MIT (modified): see f()", rock.licence)
end

function T:test_parse_rockspec_checks_the_shape()
  self:assert_not_nil(select(2, licences.parse_rockspec("package = 1\nversion = 'x'")))
  self:assert_not_nil(select(2, licences.parse_rockspec('package = "a/b"\nversion = "1-1"')))
  self:assert_not_nil(select(2, licences.parse_rockspec('package = "a"')))
  self:assert_not_nil(select(2, licences.parse_rockspec("package = 'a'\nversion = '1-1'\n" .. ("-- x\n"):rep(100000))))
  local rock = licences.parse_rockspec('package = "a"\nversion = "1-1"\ndescription = { license = 5 }\ndependencies = "x"')
  self:assert_nil(rock.licence)
  self:assert_equal(0, #rock.dependencies)
end

function T:test_read_lists_the_installed_rocks_sorted_with_their_licence_texts()
  local files = {}
  add_rock(files, "zeta", "2.0-1", "MIT", nil, { ["LICENSE"] = "Zeta licence text\n" })
  add_rock(files, "alpha", "1.0-1", "BSD-2-Clause", nil, { ["doc/COPYING.md"] = "Alpha copying text" })
  add_rock(files, "alpha", "0.9-1", "BSD-2-Clause")
  local model = licences.read(doc.MemoryFileSystem(files), tree_options())
  local names = {}
  for _, rock in ipairs(model.rocks) do names[#names + 1] = rock.name .. " " .. rock.version end
  self:assert_equal("alpha 0.9-1,alpha 1.0-1,zeta 2.0-1", table.concat(names, ","))
  self:assert_nil(model.rocks[1].text)
  self:assert_equal("Alpha copying text", model.rocks[2].text)
  self:assert_equal("Zeta licence text\n", model.rocks[3].text)
  self:assert_equal(0, #model.problems)
end

function T:test_read_resolves_the_dependencies_of_the_roots_transitively()
  local files = {}
  add_rock(files, "app", "1-1", "MIT", { "mid" })
  add_rock(files, "mid", "1-1", "MIT", { "leaf", "app" })
  add_rock(files, "leaf", "1-1", "ISC")
  add_rock(files, "unused", "1-1", "GPL-3.0-only")
  local model = licences.read(doc.MemoryFileSystem(files), tree_options({ root_rocks = { "app" } }))
  local names = {}
  for _, rock in ipairs(model.rocks) do names[#names + 1] = rock.name end
  self:assert_equal("app,leaf,mid", table.concat(names, ","))
  self:assert_equal("mid", table.concat(model.rocks[1].required_by, ","), "required by the rocks that depend on it")
end

function T:test_read_reports_what_it_cannot_resolve_or_read()
  local files = {}
  add_rock(files, "app", "1-1", "MIT", { "ghost" })
  files[TREE .. "/broken/1-1/broken-1-1.rockspec"] = 'package = "broken"\nversion = "1-1"\nos.exit(1)'
  files[TREE .. "/liar/1-1/liar-1-1.rockspec"] = rockspec("other", "1-1", "MIT")
  local model = licences.read(doc.MemoryFileSystem(files), tree_options())
  local problems = table.concat(model.problems, "\n")
  self:assert_true(has(problems, "broken"), problems)
  self:assert_true(has(problems, "liar"), problems)
  local resolved = licences.read(doc.MemoryFileSystem(files), tree_options({ root_rocks = { "app", "nowhere" } }))
  problems = table.concat(resolved.problems, "\n")
  self:assert_true(has(problems, "ghost"), problems)
  self:assert_true(has(problems, "nowhere"), problems)
end

function T:test_read_without_a_tree_reports_it()
  local model = licences.read(doc.MemoryFileSystem({}), tree_options())
  self:assert_equal(0, #model.rocks)
  self:assert_true(has(model.problems[1], "tree"), model.problems[1])
end

function T:test_read_does_not_follow_links_and_bounds_the_number_of_rocks()
  local files = {}
  for index = 1, 12 do add_rock(files, ("rock%02d"):format(index), "1-1", "MIT") end
  local fs = doc.MemoryFileSystem(files)
  fs.is_link = function(_, path) return path:find("rock03", 1, true) ~= nil end
  local model = licences.read(fs, tree_options({ max_rocks = 5 }))
  self:assert_equal(5, #model.rocks)
  self:assert_true(has(table.concat(model.problems, "\n"), "5"), "the limit is reported")
  for _, rock in ipairs(model.rocks) do self:assert_true(rock.name ~= "rock03") end
end

function T:test_page_lists_rocks_and_groups_equal_texts()
  local files = {}
  add_rock(files, "a", "1-1", "MIT", nil, { ["LICENSE"] = "MIT text\n" })
  add_rock(files, "b", "2-1", "MIT", nil, { ["LICENSE"] = "MIT text\n" })
  add_rock(files, "c", "3-1", "ISC")
  local model = licences.read(doc.MemoryFileSystem(files), tree_options())
  local page = licences.markdown(model, { "# Third-party licences", "" })
  self:assert_true(has(page, "| `a` | 1-1 | `MIT` |"), page)
  self:assert_true(has(page, "| `c` | 3-1 | `ISC` |"), page)
  local _, count = page:gsub("MIT text", "")
  self:assert_equal(1, count, "one copy of a text shared by two rocks")
  self:assert_true(has(page, "`a` 1-1"), page)
  self:assert_true(has(page, "`b` 2-1"), page)
  self:assert_true(has(page, "no licence text"), "the rock without a text is named")
  self:assert_equal(page, licences.markdown(model, { "# Third-party licences", "" }), "deterministic")
end

function T:test_page_treats_the_data_of_a_rock_as_data()
  local files = {}
  add_rock(files, "evil", "1-1", "<script>alert(1)</script> | **MIT**", nil,
    { ["LICENSE"] = "text with a fence ```` and <b>html</b>\n```\nstill text\n" })
  local model = licences.read(doc.MemoryFileSystem(files), tree_options())
  local page = licences.markdown(model, { "# T", "" })
  local html = require("hecate.doc.markdown").render(page).html
  self:assert_nil(html:find("<script>", 1, true), "the rendered page holds no raw HTML of the rock")
  self:assert_nil(html:find("<b>html</b>", 1, true))
  self:assert_true(has(page, "\\|"), "pipes of a cell are escaped")
  self:assert_true(has(page, "`````\ntext with a fence"), "the fence is longer than any run of the text")
end

function T:test_a_licence_text_that_is_not_text_is_not_reproduced()
  local files = {}
  add_rock(files, "bin", "1-1", "MIT", nil, { ["LICENSE"] = "caf\xE9 \xFF broken" })
  add_rock(files, "huge", "1-1", "MIT", nil, { ["LICENSE"] = ("x"):rep(200 * 1024) })
  local model = licences.read(doc.MemoryFileSystem(files), tree_options())
  self:assert_nil(model.rocks[1].text)
  self:assert_nil(model.rocks[2].text)
  local problems = table.concat(model.problems, "\n")
  self:assert_true(has(problems, "bin") and has(problems, "huge"), problems)
end

function T:test_bundled_reproduces_the_texts_of_the_theme()
  local items = licences.bundled({ diagrams = false })
  local by_name = {}
  for _, item in ipairs(items) do by_name[item.name] = item end
  for _, name in ipairs({ "STIX Two Text", "Fira Sans", "Fira Code" }) do
    self:assert_equal("OFL-1.1", by_name[name].licence)
    self:assert_true(has(by_name[name].text, "SIL OPEN FONT LICENSE Version 1.1"), name)
  end
  self:assert_true(has(by_name["STIX Two Text"].text, "STIX Fonts Project"))
  self:assert_true(has(by_name["Hecate brand marks"].text, "MIT License"))
  self:assert_equal("MIT", by_name["Octicons mark-github"].licence)
  self:assert_true(has(by_name["Octicons mark-github"].text, "GitHub, Inc."))
  self:assert_not_nil(by_name["comrak"], "the native renderer is named")
  self:assert_nil(by_name["Mermaid"], "Mermaid is bundled only when a page holds a diagram")
end

function T:test_the_note_of_two_face_gives_the_counts_of_the_locked_version()
  -- THIRD_PARTY_NOTICES, section 5 (two-face 0.5.2): 66 licence files, MIT 50, Apache-2.0 13, BSD-2-Clause 2, BSD-3-Clause 1.
  local by_name = {}
  for _, item in ipairs(licences.bundled({ diagrams = false })) do by_name[item.name] = item end
  local note = by_name["two-face"].note
  for _, text in ipairs({ "66 licence files", "MIT (50)", "Apache-2.0 (13)", "BSD-2-Clause (2)", "BSD-3-Clause (1)" }) do
    self:assert_not_nil(note:find(text, 1, true), text)
  end
  self:assert_nil(note:find("MIT (48)", 1, true), "the counts of the audit of 2026-10-21 are superseded")
end

function T:test_bundled_adds_mermaid_with_its_components_when_a_diagram_is_used()
  local items = licences.bundled({ diagrams = true })
  local mermaid
  for _, item in ipairs(items) do mermaid = item.name == "Mermaid" and item or mermaid end
  self:assert_equal("MIT", mermaid.licence)
  self:assert_true(has(mermaid.text, "Knut Sveidqvist"))
  self:assert_true(has(mermaid.note, "EPL-2.0"), "the licences of the bundled components are named")
end

function T:test_bundled_reads_the_theme_from_the_given_directory()
  ---@diagnostic disable-next-line: missing-fields  -- a reader with `read` only: the theme is read, never written
  local items = licences.bundled({ diagrams = false, theme_files_dir = "t", theme_file_system = {
    read = function(_, path) return path == "t/brand/LICENSE" and "custom brand text" or nil end,
  } })
  local brand
  for _, item in ipairs(items) do brand = item.name == "Hecate brand marks" and item or brand end
  self:assert_equal("custom brand text", brand.text)
end

function T:test_the_theme_assets_the_page_names_exist()
  local directory = theme.assets_directory()
  for _, path in ipairs({ "fonts/OFL-stix-two-text.txt", "fonts/OFL-fira-sans.txt", "fonts/OFL-fira-code.txt",
    "brand/LICENSE", "mermaid/LICENSE" }) do
    local file = io.open(directory .. "/" .. path, "rb")
    self:assert_not_nil(file, path)
    file:close()
  end
end

local function build_options(fs, extra)
  local options = {
    site_configuration = { title = "Shop" }, guides_dir = "docs", output_dir = "dist", file_system = fs,
  }
  for key, value in pairs(extra or {}) do options[key] = value end
  -- The guides come from the content trees of the audiences: the home page of each tree is written there first.
  for _, audience in ipairs(options.audiences or { "maintainer" }) do
    fs:write((options.project_dir and (options.project_dir .. "/") or "") .. "docs/" .. audience .. "/en/index.md", "# Shop\n")
  end
  return options
end

local generate = doc.generate_project_documentation

local function tree_files()
  local files = {}
  add_rock(files, "pkg", "1-1", "MIT", nil, { ["LICENSE"] = "Pkg licence text\n" })
  local moved = {}
  for path, text in pairs(files) do moved["lm/" .. path] = text end
  return moved
end

function T:test_build_does_not_generate_the_page_by_default()
  local fs = doc.MemoryFileSystem(tree_files())
  generate(build_options(fs))
  self:assert_nil(fs:read("docs/maintainer/en/third-party-licences.md"))
end

function T:test_build_generates_a_maintainer_page_from_the_tree()
  local fs = doc.MemoryFileSystem(tree_files())
  local report = generate(build_options(fs, { licences_page = { rocks_tree_dir = "lm/tree" }, fail_on_problems = true }))
  self:assert_equal(0, #report.problems, table.concat(report.problems, "\n"))
  local source = fs:read("docs/maintainer/en/third-party-licences.md")
  self:assert_true(project.is_generated(source))
  self:assert_nil(source:find("\naudience:", 1, true), "no `audience` key: the tree is the audience")
  self:assert_true(has(source, "Pkg licence text"))
  self:assert_true(has(source, "STIX Two Text"))
  self:assert_not_nil(fs:read("dist/maintainer/en/third-party-licences/index.html"))
  self:assert_nil(fs:read("dist/maintainer/assets/mermaid/mermaid.min.js"))
end

function T:test_build_writes_the_page_into_the_maintainer_tree_and_not_into_the_user_tree()
  local fs = doc.MemoryFileSystem(tree_files())
  generate(build_options(fs, { licences_page = { rocks_tree_dir = "lm/tree" }, audiences = { "user", "maintainer" } }))
  self:assert_not_nil(fs:read("docs/maintainer/en/third-party-licences.md"))
  self:assert_nil(fs:read("docs/user/en/third-party-licences.md"))
  self:assert_not_nil(fs:read("dist/maintainer/en/third-party-licences/index.html"))
  self:assert_nil(fs:read("dist/user/en/third-party-licences/index.html"))
end

function T:test_build_can_write_the_page_into_the_user_tree()
  local fs = doc.MemoryFileSystem(tree_files())
  generate(build_options(fs, { licences_page = { rocks_tree_dir = "lm/tree", audience = "user" },
    audiences = { "user", "maintainer" } }))
  self:assert_not_nil(fs:read("dist/user/en/third-party-licences/index.html"))
  self:assert_nil(fs:read("dist/maintainer/en/third-party-licences/index.html"))
  self:assert_nil(fs:read("docs/maintainer/en/third-party-licences.md"))
  -- Moving the page from one tree to the other removes the stale generated page of the first.
  generate(build_options(fs, { licences_page = { rocks_tree_dir = "lm/tree" }, audiences = { "user", "maintainer" } }))
  self:assert_nil(fs:read("docs/user/en/third-party-licences.md"), "stale in the tree it left")
  self:assert_not_nil(fs:read("docs/maintainer/en/third-party-licences.md"))
end

function T:test_the_audience_of_the_page_is_one_of_the_trees_that_are_built_and_defaults_to_the_only_one()
  local fs = doc.MemoryFileSystem(tree_files())
  -- Only the user tree is built: the page goes there (the default `maintainer` is not built).
  generate(build_options(fs, { licences_page = { rocks_tree_dir = "lm/tree" }, audiences = { "user" } }))
  self:assert_not_nil(fs:read("docs/user/en/third-party-licences.md"))
  self:assert_nil(fs:read("docs/maintainer/en/third-party-licences.md"))
  -- A tree that is not listed cannot be chosen.
  local err = self:assert_error(function()
    generate(build_options(fs, { licences_page = { rocks_tree_dir = "lm/tree", audience = "user" } }))
  end)
  self:assert_equal("licences_page.audience", err.context.argument)
  self:assert_true(has(tostring(err), "listed in `audiences`"), tostring(err))
end

function T:test_build_names_mermaid_only_when_a_guide_holds_a_diagram()
  local fs = doc.MemoryFileSystem(tree_files())
  local options = build_options(fs, { licences_page = { rocks_tree_dir = "lm/tree" } })
  fs:write("docs/maintainer/en/index.md", "# Shop\n\n```mermaid\ngraph TD\n  A --> B\n```\n")
  generate(options)
  self:assert_true(has(fs:read("docs/maintainer/en/third-party-licences.md"), "Knut Sveidqvist"))
  local plain = doc.MemoryFileSystem(tree_files())
  generate(build_options(plain, { licences_page = { rocks_tree_dir = "lm/tree" } }))
  self:assert_nil(plain:read("docs/maintainer/en/third-party-licences.md"):find("Knut Sveidqvist", 1, true))
end

function T:test_build_reports_the_problems_of_the_tree_and_removes_a_stale_page()
  local fs = doc.MemoryFileSystem(tree_files())
  local report = generate(build_options(fs, { licences_page = { rocks_tree_dir = "nowhere" } }))
  self:assert_true(has(table.concat(report.problems, "\n"), "nowhere"))
  generate(build_options(fs, { licences_page = { rocks_tree_dir = "lm/tree" } }))
  self:assert_not_nil(fs:read("docs/maintainer/en/third-party-licences.md"))
  generate(build_options(fs))
  self:assert_nil(fs:read("docs/maintainer/en/third-party-licences.md"), "a generated page that is no longer produced is removed")
end

function T:test_build_never_overwrites_a_guide_with_the_page()
  local fs = doc.MemoryFileSystem(tree_files())
  fs:write("docs/maintainer/en/third-party-licences.md", "# mine\n")
  local err = self:assert_error(function() generate(build_options(fs, { licences_page = { rocks_tree_dir = "lm/tree" } })) end)
  self:assert_true(has(tostring(err), "not generated"))
  self:assert_equal("# mine\n", fs:read("docs/maintainer/en/third-party-licences.md"))
end

function T:test_build_checks_the_licences_page_option()
  local fs = doc.MemoryFileSystem({})
  for _, bad in ipairs({ "yes", { rocks_tree_dir = 1 }, { root_rocks = "x" }, { root_rocks = { 1 } },
    { audience = "other" }, { include_bundled = "no" } }) do
    local err = self:assert_error(function() generate(build_options(fs, { licences_page = bad })) end)
    self:assert_true(has(tostring(err), "licences_page"), tostring(err))
  end
end

function T:test_the_old_american_option_name_is_not_an_alias()
  local fs = doc.MemoryFileSystem(tree_files())
  local err = self:assert_error(function() generate(build_options(fs, { licenses_page = { rocks_tree_dir = "lm/tree" } })) end)
  self:assert_equal("licenses_page", err.context.argument)
  self:assert_not_nil(tostring(err):find("renamed `licences_page`", 1, true), tostring(err))
  self:assert_nil(fs:read("docs/maintainer/en/third-party-licences.md"))
end

function T:test_licences_page_true_reads_lua_modules()
  local files = {}
  add_rock(files, "pkg", "1-1", "MIT")
  local moved = {}
  for path, text in pairs(files) do moved["lua_modules/" .. path:sub(#"tree/" + 1)] = text end
  local fs = doc.MemoryFileSystem(moved)
  generate(build_options(fs, { licences_page = true }))
  self:assert_true(has(fs:read("docs/maintainer/en/third-party-licences.md"), "`pkg`"))
end

function T:test_the_rocks_tree_is_relative_to_the_project_directory()
  local files = {}
  add_rock(files, "pkg", "1-1", "MIT")
  local moved = {}
  for path, text in pairs(files) do moved["acme/lua_modules/" .. path:sub(#"tree/" + 1)] = text end
  local fs = doc.MemoryFileSystem(moved)
  generate(build_options(fs, { project_dir = "acme", licences_page = true }))
  self:assert_true(has(fs:read("acme/docs/maintainer/en/third-party-licences.md"), "`pkg`"))
end

return T
