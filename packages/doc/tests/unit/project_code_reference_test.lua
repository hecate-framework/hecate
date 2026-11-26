---@diagnostic disable: need-check-nil, undefined-field  -- tests read files they have just generated; a nil fails the assertion that follows
-- The code reference of a project, end to end through `generate_project_documentation`, without a real LuaLS: the
-- exporter (`hecate.doc.luals.export`) and the version probe are replaced by stubs that return a fixed export. What is
-- tested is everything around the exporter: the pages written below `reference/<package>/` of the audience trees (public
-- symbols into the `user` tree and internals into the `maintainer` tree when both are built, the whole reference into the one
-- tree otherwise), the pages of the internals only where the maintainer tree is built, a hand-written page that is never
-- overwritten, the removal of stale generated pages, and the sites built from the pages. The test with the real LuaLS is `tests/integration/reference_test.lua` (it does nothing without LuaLS).
local test = require("harness.test")
local doc = require("hecate.doc")
local json = require("hecate.json")
local luals = require("hecate.doc.luals")
local front_matter = require("hecate.doc.front_matter")
local T = test.Case("ProjectCodeReferenceTest")

local function class(name, file, visible, description, extra)
  local entry = { name = name, type = "type", fields = {}, rawdesc = " " .. description .. ".",
    defines = { { type = "doc.class", file = file, visible = visible, rawdesc = " " .. description .. "." } } }
  for key, value in pairs(extra or {}) do entry[key] = value end
  return entry
end

local ROOT = class("hecate.shop", "hecate/shop/init.lua", "public", "The shop")
local CART = class("hecate.shop.Cart", "hecate/shop/cart.lua", "public", "A cart of items")
local STORE = class("hecate.shop.internal.Store", "hecate/shop/internal/store.lua", "public", "The store behind the cart")
local RESTRICTED = class("hecate.shop.Restricted", "hecate/shop/restricted.lua", "package", "A class that is not public")

local original_export, original_version

function T:set_up()
  original_export, original_version = luals.export, luals.version
  self.calls = {}
  self.export = { ROOT, CART, STORE, RESTRICTED }
  luals.version = function() return luals.PINNED end
  luals.export = function(executable, sources_dir, options)
    self.calls[#self.calls + 1] = { executable = executable, sources_dir = sources_dir, options = options }
    return json.encode(self.export)
  end
end

function T:tear_down() luals.export, luals.version = original_export, original_version end

local function files(extra)
  local out = {
    ["shop/docs/user/en/index.md"] = "---\ntitle: Shop\n---\nwelcome\n",
    ["shop/docs/maintainer/en/index.md"] = "---\ntitle: Shop team\n---\nwelcome\n",
    ["shop/docs/maintainer/en/internals.md"] = "---\ntitle: Internals\n---\nhow it works\n",
    ["shop/src/hecate/shop/init.lua"] = "-- sources are not read: the exporter is a stub\n",
  }
  for path, data in pairs(extra or {}) do out[path] = data end
  return out
end

-- The default of a project is the maintainer tree alone.
local function generate(self, fs, options)
  local arguments = { project_dir = "shop", guides_dir = "docs", output_dir = "dist", file_system = fs, package_name = "shop",
    language_server_path = "stub-luals", site_configuration = { title = "Shop" } }
  for key, value in pairs(options or {}) do arguments[key] = value end
  local report = doc.generate_project_documentation(arguments)
  self:assert_equal(1, #self.calls, "one export, of the one package")
  return report
end

local BOTH = { "user", "maintainer" }
local MAINTAINER_REFERENCE = "shop/docs/maintainer/en/reference/shop/"
local USER_REFERENCE = "shop/docs/user/en/reference/shop/"
local REFERENCE = MAINTAINER_REFERENCE

local function names(fs, directory)
  local out = {}
  for _, entry in ipairs(fs:list(directory) or {}) do out[#out + 1] = entry.name end
  return table.concat(out, ",")
end

function T:test_the_exporter_is_called_once_for_the_sources_of_the_project_with_the_given_executable()
  local fs = doc.MemoryFileSystem(files())
  local report = generate(self, fs)
  self:assert_equal("stub-luals", self.calls[1].executable)
  self:assert_equal("shop/src", self.calls[1].sources_dir)
  self:assert_nil(self.calls[1].options.language_server_config_path, "none is passed when the option is unset")
  self:assert_nil(report.code.skipped)
  self:assert_equal(4, report.code.pages)
  self:assert_equal("shop", report.code.packages[1])
  self:assert_equal(0, #report.code.problems, table.concat(report.code.problems, "\n"))
end

function T:test_with_both_audiences_public_symbols_go_to_the_user_tree_and_the_internals_to_the_maintainer_tree()
  local fs = doc.MemoryFileSystem(files())
  generate(self, fs, { audiences = BOTH })
  self:assert_equal("Cart.md,index.md", names(fs, USER_REFERENCE:gsub("/$", "")))
  self:assert_equal("Restricted.md,Store.md", names(fs, MAINTAINER_REFERENCE:gsub("/$", "")))
  for _, path in ipairs({ USER_REFERENCE .. "index.md", USER_REFERENCE .. "Cart.md", MAINTAINER_REFERENCE .. "Store.md",
    MAINTAINER_REFERENCE .. "Restricted.md" }) do
    local text = assert(fs:read(path), path)
    self:assert_true(doc.project.is_generated(text), path .. " is marked as generated")
    self:assert_true(text:find("generated: true", 1, true) ~= nil, path)
    self:assert_nil(front_matter.parse(text).audience, path .. ": no `audience` key, the tree is the audience")
  end
  -- Each tree is built into its own site, with the pages of its tree only.
  for _, name in ipairs({ "", "Cart/" }) do
    self:assert_not_nil(fs:read("shop/dist/user/en/reference/shop/" .. name .. "index.html"), "user site: " .. name)
    self:assert_nil(fs:read("shop/dist/maintainer/en/reference/shop/" .. name .. "index.html"), "maintainer site: " .. name)
  end
  for _, name in ipairs({ "Store/", "Restricted/" }) do
    self:assert_nil(fs:read("shop/dist/user/en/reference/shop/" .. name .. "index.html"), "user site: " .. name)
    self:assert_not_nil(fs:read("shop/dist/maintainer/en/reference/shop/" .. name .. "index.html"), "maintainer site: " .. name)
  end
  -- The search index of a site has the pages of its tree only.
  local user_search = fs:read("shop/dist/user/assets/search-en.js")
  self:assert_nil(user_search:find("/Store/", 1, true), "no document for a page of the other tree")
  self:assert_nil(user_search:find("/Restricted/", 1, true))
  local maintainer_search = fs:read("shop/dist/maintainer/assets/search-en.js")
  self:assert_not_nil(maintainer_search:find("en/reference/shop/Store/index.html", 1, true))
  self:assert_nil(maintainer_search:find("/Cart/", 1, true))
end

function T:test_a_clean_project_build_with_both_audiences_and_both_home_pages_reports_no_problem()
  local fs = doc.MemoryFileSystem(files())
  local report = generate(self, fs, { audiences = BOTH, fail_on_problems = true })
  self:assert_equal(0, #report.problems, table.concat(report.problems, "\n"))
  self:assert_equal(0, #report.code.problems)
  self:assert_equal(2, #report.sites)
  self:assert_equal(0, #report.sites[1].problems)
  self:assert_equal(0, #report.sites[2].problems)
  -- The module page of the user tree names the classes of its audience only, and no page of one tree links to the other.
  local module = fs:read(USER_REFERENCE .. "index.md")
  self:assert_not_nil(module:find("](Cart.md)", 1, true), module)
  self:assert_nil(module:find("Store", 1, true), "the internal class is not")
  self:assert_nil(module:find("Restricted", 1, true))
  self:assert_nil(module:find("The store behind the cart", 1, true), "nor its summary")
  for _, name in ipairs({ "Store.md", "Restricted.md" }) do
    self:assert_nil(fs:read(MAINTAINER_REFERENCE .. name):find("](index.md", 1, true), name .. " does not link to the user module page")
  end
  -- One tree: the module page lists every class it has, and the pages link back to it.
  local one = doc.MemoryFileSystem(files())
  self.calls = {}
  generate(self, one)
  local one_module = one:read(REFERENCE .. "index.md")
  self:assert_not_nil(one_module:find("Store", 1, true))
  self:assert_not_nil(one_module:find("Restricted", 1, true))
  self:assert_not_nil(one:read(REFERENCE .. "Store.md"):find("index.md", 1, true), "one tree keeps the link back")
end

function T:test_with_one_audience_the_whole_reference_goes_into_its_tree()
  -- Users only: the internals are not even generated, and the maintainer tree is not touched.
  local fs = doc.MemoryFileSystem(files())
  generate(self, fs, { audiences = { "user" } })
  self:assert_equal("Cart.md,index.md", names(fs, USER_REFERENCE:gsub("/$", "")))
  self:assert_nil(fs:list(MAINTAINER_REFERENCE:gsub("/$", "")), "the maintainer tree is not built and not written")
  self:assert_nil(fs:read("shop/dist/maintainer/en/index.html"))
  self:assert_nil(fs:read("shop/dist/user/en/reference/shop/Store/index.html"))
  self:assert_not_nil(fs:read("shop/dist/user/en/reference/shop/Cart/index.html"))
  -- Maintainers only (the default of a project): the whole reference.
  local second = doc.MemoryFileSystem(files())
  self.calls = {}
  generate(self, second)
  self:assert_equal("Cart.md,Restricted.md,Store.md,index.md", names(second, REFERENCE:gsub("/$", "")))
  self:assert_nil(second:list(USER_REFERENCE:gsub("/$", "")))
  self:assert_not_nil(second:read("shop/dist/maintainer/en/reference/shop/Store/index.html"))
  self:assert_nil(second:read("shop/dist/user/en/index.html"), "the user tree is not listed: not built, and not an error")
end

function T:test_the_reference_site_takes_one_locale_directory_or_one_per_audience_never_both()
  local reference_site = require("hecate.doc.reference_site")
  local fs = doc.MemoryFileSystem(files())
  for _, extra in ipairs({
    { locale_dir = "a", audience_locale_dirs = { user = "u", maintainer = "m" } },
    { audience_locale_dirs = { user = "u" } },
    { audience_locale_dirs = "u" },
  }) do
    local options = { project_dir = "shop", file_system = fs, language_server_path = "stub-luals" }
    for key, value in pairs(extra) do options[key] = value end
    local err = self:assert_error(function() reference_site.run(options) end)
    self:assert_equal("audience_locale_dirs", err.context.argument)
  end
  self:assert_equal(0, #self.calls, "refused before LuaLS runs")
end

function T:test_a_hand_written_page_in_the_reference_directory_of_the_package_is_never_overwritten_and_nothing_is_replaced()
  local handwritten = "---\ntitle: Notes\n---\nWritten by hand.\n"
  local fs = doc.MemoryFileSystem(files({ [REFERENCE .. "notes.md"] = handwritten }))
  local report = generate(self, fs)
  self:assert_equal(handwritten, fs:read(REFERENCE .. "notes.md"))
  self:assert_equal("notes.md", names(fs, REFERENCE:gsub("/$", "")), "the directory is left alone: no generated page is mixed with it")
  local reported = false
  for _, problem in ipairs(report.problems) do
    if problem:find("holds files that are not generated; left alone", 1, true) then reported = true end
  end
  self:assert_true(reported, table.concat(report.problems, "\n"))
  self:assert_not_nil(fs:read("shop/dist/maintainer/en/reference/shop/notes/index.html"), "the hand-written page is published")
end

function T:test_a_hand_written_page_beside_the_reference_directory_of_the_package_stays_and_the_package_is_generated()
  local handwritten = "---\ntitle: Overview\norder: 1\n---\nThe reference, introduced by hand.\n"
  local fs = doc.MemoryFileSystem(files({ ["shop/docs/maintainer/en/reference/index.md"] = handwritten,
    ["shop/docs/maintainer/en/reference/other/a.md"] = "---\ntitle: A\n---\na\n" }))
  generate(self, fs)
  self:assert_equal(handwritten, fs:read("shop/docs/maintainer/en/reference/index.md"))
  self:assert_equal("---\ntitle: A\n---\na\n", fs:read("shop/docs/maintainer/en/reference/other/a.md"))
  self:assert_not_nil(fs:read(REFERENCE .. "Cart.md"))
end

function T:test_a_generated_page_that_the_export_no_longer_has_is_removed_and_the_others_are_rewritten()
  local fs = doc.MemoryFileSystem(files({
    [REFERENCE .. "Gone.md"] = "---\ntitle: Gone\ngenerated: true\n---\n\n# hecate.shop.Gone\n",
    [REFERENCE .. "functions/old.md"] = "---\ntitle: old\ngenerated: true\n---\n\n# old\n",
  }))
  generate(self, fs)
  self:assert_nil(fs:read(REFERENCE .. "Gone.md"), "a stale page is removed")
  self:assert_nil(fs:read(REFERENCE .. "functions/old.md"))
  self:assert_equal("Cart.md,Restricted.md,Store.md,index.md", names(fs, REFERENCE:gsub("/$", "")))
  -- A second run with a smaller export removes what the first wrote.
  self.export = { ROOT, CART }
  self.calls = {}
  generate(self, fs, { clean_output_dir = true })
  self:assert_equal("Cart.md,index.md", names(fs, REFERENCE:gsub("/$", "")))
  self:assert_nil(fs:read("shop/dist/maintainer/en/reference/shop/Store/index.html"), "the site is rebuilt from the pages that are left")
  self:assert_not_nil(fs:read("shop/dist/maintainer/en/reference/shop/Cart/index.html"))
  -- With both trees, a tree that has no page of the package any more loses its generated directory.
  local both = doc.MemoryFileSystem(files())
  self.export = { ROOT, CART, STORE, RESTRICTED }
  self.calls = {}
  generate(self, both, { audiences = BOTH })
  self:assert_equal("Restricted.md,Store.md", names(both, MAINTAINER_REFERENCE:gsub("/$", "")))
  self.export = { ROOT, CART }
  self.calls = {}
  generate(self, both, { audiences = BOTH })
  self:assert_nil(both:list(MAINTAINER_REFERENCE:gsub("/$", "")), "no internal page is left in the maintainer tree")
  self:assert_equal("Cart.md,index.md", names(both, USER_REFERENCE:gsub("/$", "")))
end

function T:test_the_pages_are_the_same_on_every_run()
  local first = doc.MemoryFileSystem(files())
  generate(self, first, { audiences = BOTH })
  local second = doc.MemoryFileSystem(files())
  self.calls = {}
  generate(self, second, { audiences = BOTH })
  for _, path in ipairs({ USER_REFERENCE .. "index.md", USER_REFERENCE .. "Cart.md", MAINTAINER_REFERENCE .. "Store.md",
    MAINTAINER_REFERENCE .. "Restricted.md" }) do
    self:assert_equal(first:read(path), second:read(path), path)
  end
  -- And a run over the output of the previous one changes nothing.
  local before = first:read(USER_REFERENCE .. "Cart.md")
  self.calls = {}
  generate(self, first, { audiences = BOTH })
  self:assert_equal(before, first:read(USER_REFERENCE .. "Cart.md"))
end

function T:test_a_stub_export_that_is_not_json_is_a_problem_and_no_page_is_written()
  local fs = doc.MemoryFileSystem(files())
  luals.export = function(executable, sources_dir, options)
    self.calls[#self.calls + 1] = { executable = executable, sources_dir = sources_dir, options = options }
    return "{ not json"
  end
  local report = generate(self, fs)
  self:assert_equal(0, report.code.pages)
  local found = false
  for _, problem in ipairs(report.problems) do found = found or problem:find("the LuaLS export cannot be read", 1, true) ~= nil end
  self:assert_true(found, table.concat(report.problems, "\n"))
  self:assert_nil(fs:list(REFERENCE:gsub("/$", "")), "no reference directory")
end

function T:test_a_missing_sources_directory_is_a_problem_and_the_exporter_is_not_called()
  local fs = doc.MemoryFileSystem({ ["shop/docs/maintainer/en/index.md"] = "---\ntitle: Shop\n---\nwelcome\n" })
  local report = doc.generate_project_documentation({ project_dir = "shop", guides_dir = "docs", output_dir = "dist", file_system = fs,
    package_name = "shop", language_server_path = "stub-luals", site_configuration = { title = "Shop" } })
  self:assert_equal(0, #self.calls)
  local found = false
  for _, problem in ipairs(report.problems) do found = found or problem:find("package shop has no src directory at shop/src", 1, true) ~= nil end
  self:assert_true(found, table.concat(report.problems, "\n"))
end

return T
