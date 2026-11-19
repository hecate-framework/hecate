---@diagnostic disable: need-check-nil, undefined-field  -- tests read files they have just built; a nil fails the assertion that follows
-- Builds are deterministic (the invariant of `packages/doc/CLAUDE.md`): the same tree, whatever the order in which its files
-- were created, gives the same files in the same order of writing, the same problems in the same order, and the same
-- error when two files are broken at once. The tree is created in the sorted order, the reverse order and several
-- seeded shuffles, with enough files in each directory that an unsorted `pairs` would differ from the sorted order.
local test = require("harness.test")
local doc = require("hecate.doc")
local core = require("hecate.core")
local Site = require("hecate.doc.site")
local T = test.Case("SiteDeterminismTest")

local function page(title, body, extra)
  return ("---\ntitle: %s\n%s---\n%s\n"):format(title, extra or "", body or "text")
end

--- The files of the tree, as a list { path, data } in the sorted order of the path.
local function tree()
  local files = {}
  local function add(path, data) files[#files + 1] = { path = "c/" .. path, data = data } end
  -- English: several broken links, several bad pages, assets of one directory, both audiences, sections that are not in the top links.
  add("en/index.md", page("Home", "[one](nope-one.md) [two](nope-two/) [three](missing/three.md) ![p](img/absent.png) [hidden](internals/design.md)"))
  add("en/guide/index.md", page("Guide", "start", "order: 1\n"))
  add("en/guide/a.md", page("Alpha", "[x](x1.md) [y](y1.md) [z](z1.png)", "order: 2\n"))
  add("en/guide/b.md", page("Beta", "[x](x2.md) [y](y2.md)", "order: 3\n"))
  add("en/guide/c.md", "No title here, and no heading.\n")
  add("en/guide/d.md", "---\norder: 5\n---\n## Heading {#sidebar}\n\ntext\n")
  add("en/guide/e.md", page("Echo", "e", "order: 6\naudience: maintainer\n"))
  add("en/internals/index.md", page("Internals", "i", "audience: maintainer\n"))
  add("en/internals/design.md", page("Design", "[nowhere](gone.md)", "audience: maintainer\n"))
  for index = 1, 9 do
    local name = string.char(string.byte("a") + index - 1) .. "-section"
    add(("en/%s/index.md"):format(name), page("Section " .. name, "s", "audience: maintainer\n"))
    add(("en/%s/p.md"):format(name), page("P " .. name, "[bad](bad-" .. index .. ".md)", "audience: maintainer\n"))
  end
  for index = 1, 14 do add(("en/img/p%02d.png"):format(index), "png" .. index) end
  for index = 1, 6 do add(("en/img/sub/q%d.png"):format(index), "q" .. index) end
  add("en/guide/pic.svg", "<svg/>")
  -- French: a translation with its own broken link, an asset of its own.
  add("fr/index.md", page("Accueil", "[x](introuvable.md)"))
  add("fr/guide/a.md", page("Alpha fr", "[x](x1.md) [y](y1.md)"))
  add("fr/img/f1.png", "f1")
  add("fr/img/f2.png", "f2")
  -- public/: files in several directories.
  for index = 1, 10 do add(("public/files/f%02d.txt"):format(index), "f" .. index) end
  add("public/brand/logo.svg", "<svg/>")
  add("public/robots.txt", "User-agent: *\n")
  add("public/deep/er/er/file.txt", "deep")
  table.sort(files, function(a, b) return a.path < b.path end)
  return files
end

local function ordered(files, how, seed)
  local list = table.move(files, 1, #files, 1, {})
  if how == "reverse" then
    for index = 1, #list // 2 do list[index], list[#list - index + 1] = list[#list - index + 1], list[index] end
  elseif how == "shuffle" then
    math.randomseed(seed)
    for index = #list, 2, -1 do
      local other = math.random(1, index)
      list[index], list[other] = list[other], list[index]
    end
  end
  return list
end

local function orders()
  local out = { { "sorted" }, { "reverse" } }
  for seed = 1, 6 do out[#out + 1] = { "shuffle", seed * 7919 } end
  return out
end

--- A file system over a memory file system, filled in the given order, that records the order of the writes it receives.
local function recording(list)
  local inner = doc.MemoryFileSystem()
  for _, file in ipairs(list) do inner:write(file.path, file.data) end
  local log = {}
  local fs = {}
  function fs:read(path) return inner:read(path) end
  function fs:list(path) return inner:list(path) end
  function fs:exists(path) return inner:exists(path) end
  function fs:remove_tree(path) return inner:remove_tree(path) end
  function fs:is_link(path) return inner:is_link(path) end
  function fs:write(path, data)
    if path:sub(1, 2) == "o/" then log[#log + 1] = path .. "\0" .. data end
    inner:write(path, data)
  end
  return fs, log
end

local LOCALES = { { code = "en", label = "English" }, { code = "fr", label = "Fran\u{E7}ais" } }

local SEPARATE = { title = "T", locales = LOCALES, site_origin = "https://x.test", generate_llms_txt = true,
  audiences = { "user", "maintainer" }, default_audience = "user",
  top_links = { { text = "Guide", link = "guide" }, { text = "Internals", link = "internals" } } }
local MERGED = { title = "T", locales = LOCALES, site_origin = "https://x.test", generate_llms_txt = true,
  audiences = { "user", "maintainer" }, audience_sites = "merged", default_audience = "user",
  top_links = { { text = "Guide", link = "guide" } } }

local function build(list, configuration)
  local fs, log = recording(list)
  local report = doc.build({ site_configuration = configuration, guides_dir = "c", output_dir = "o", file_system = fs })
  return report, log
end

local function describe(first, other)
  for index = 1, math.max(#first, #other) do
    if first[index] ~= other[index] then
      return ("entry %d: %s  <>  %s"):format(index, (first[index] or "(none)"):gsub("%z.*", ""), (other[index] or "(none)"):gsub("%z.*", ""))
    end
  end
  return "equal"
end

function T:test_the_files_and_their_order_of_writing_do_not_depend_on_the_order_of_creation()
  for name, configuration in pairs({ separate = SEPARATE, merged = MERGED }) do
    local reference_report, reference_log = build(ordered(tree(), "sorted"), configuration)
    self:assert_true(#reference_log > 100, name .. ": the tree writes many files")
    for _, order in ipairs(orders()) do
      local report, log = build(ordered(tree(), order[1], order[2]), configuration)
      local label = ("%s, %s %s"):format(name, order[1], tostring(order[2] or ""))
      self:assert_equal(#reference_log, #log, label)
      self:assert_true(table.concat(reference_log, "\1") == table.concat(log, "\1"), label .. ": " .. describe(reference_log, log))
      self:assert_equal(reference_report.files, report.files, label)
      self:assert_equal(reference_report.bytes, report.bytes, label)
      self:assert_equal(table.concat(reference_report.problems, "\n"), table.concat(report.problems, "\n"), label)
    end
  end
end

local function paths_of(log, pattern)
  local out = {}
  for _, entry in ipairs(log) do
    local path = entry:match("^([^%z]*)")
    if path:find(pattern) then out[#out + 1] = path end
  end
  return out
end

local function ascending(list)
  for index = 2, #list do
    if list[index - 1] >= list[index] then return false, list[index - 1] .. " then " .. list[index] end
  end
  return true
end

function T:test_the_assets_the_public_files_and_the_urls_are_written_in_the_order_of_their_names()
  local _, log = build(ordered(tree(), "shuffle", 31), MERGED)
  for _, pattern in ipairs({ "^o/en/img/p", "^o/en/img/sub/", "^o/fr/img/", "^o/files/f" }) do
    local found = paths_of(log, pattern)
    self:assert_true(#found >= 2, pattern)
    local ok, why = ascending(found)
    self:assert_true(ok, pattern .. ": " .. tostring(why))
  end
  -- The sitemap lists the URLs in ascending order (the sort is not a consequence of the order of the pages).
  for _, entry in ipairs(log) do
    if entry:find("^o/sitemap%.xml%z") then
      local urls = {}
      for url in entry:gmatch("<loc>([^<]*)</loc>") do urls[#urls + 1] = url end
      self:assert_true(#urls >= 10, "several URLs")
      local ok, why = ascending(urls)
      self:assert_true(ok, "sitemap: " .. tostring(why))
    end
  end
end

function T:test_llms_txt_lists_the_sections_that_are_not_in_the_navigation_by_name()
  local fs = recording(ordered(tree(), "reverse"))
  doc.build({ site_configuration = MERGED, guides_dir = "c", output_dir = "o", file_system = fs })
  local text = fs:read("o/llms.txt")
  local headings = {}
  for heading in text:gmatch("\n## ([^\n]+)") do headings[#headings + 1] = heading end
  self:assert_equal("Guide", headings[1], "the sections of the navigation first")
  local others = {}
  for index = 2, #headings do others[#others + 1] = headings[index] end
  self:assert_true(#others >= 9, "nine sections left to the order by name: " .. table.concat(others, ", "))
  local ok, why = ascending(others)
  self:assert_true(ok, "the other sections by name: " .. tostring(why))
end

function T:test_the_problems_are_the_same_and_sorted_in_every_order()
  local reference
  for _, order in ipairs(orders()) do
    local fs = recording(ordered(tree(), order[1], order[2]))
    local site = Site({ site_configuration = MERGED, guides_dir = "c", file_system = fs }):load()
    local problems = site.problems
    self:assert_true(#problems >= 8, "several problems: " .. #problems)
    local sorted = table.move(problems, 1, #problems, 1, {})
    table.sort(sorted)
    self:assert_equal(table.concat(sorted, "\n"), table.concat(problems, "\n"), "the problems of `load` are sorted")
    local joined = table.concat(problems, "\n")
    reference = reference or joined
    self:assert_equal(reference, joined, order[1])
  end
  -- The same through `build`, per site and in total, for the separate sites.
  local report = build(ordered(tree(), "shuffle", 5), SEPARATE)
  local function check_sorted(list, label)
    for index = 2, #list do self:assert_true(list[index - 1] < list[index], label .. ": " .. list[index - 1] .. " then " .. list[index]) end
  end
  check_sorted(report.problems, "report")
  for _, site in ipairs(report.sites) do check_sorted(site.problems, site.directory) end
  self:assert_true(#report.problems >= 8)
end

function T:test_the_order_of_writing_of_a_site_is_fixed_by_the_site_not_by_the_tree()
  local function written(list)
    local fs = recording(list)
    local site = Site({ site_configuration = MERGED, guides_dir = "c", file_system = fs }):load()
    local out = {}
    site:emit(function(path) out[#out + 1] = path end)
    return table.concat(out, "\n")
  end
  local reference = written(ordered(tree(), "sorted"))
  for _, order in ipairs(orders()) do
    self:assert_equal(reference, written(ordered(tree(), order[1], order[2])), order[1] .. " " .. tostring(order[2] or ""))
  end
  -- The marker comes first, the pages of a locale before its search index, the redirect last.
  local list = {}
  for path in reference:gmatch("[^\n]+") do list[#list + 1] = path end
  self:assert_equal(doc.Site.MARKER, list[1])
  self:assert_equal("index.html", list[#list])
end

-- Two files broken at once: the error names the same one whatever the order of creation (the first by name).

local function error_of(list, configuration)
  local fs = recording(list)
  local ok, raised = pcall(doc.build, { site_configuration = configuration or { title = "T", locales = LOCALES }, guides_dir = "c",
    output_dir = "o", file_system = fs })
  return (not ok) and raised or nil
end

local function base()
  return { { path = "c/en/index.md", data = page("Home") }, { path = "c/fr/index.md", data = page("Accueil") } }
end

local function with(list, extra)
  local out = table.move(list, 1, #list, 1, {})
  for path, data in pairs(extra) do out[#out + 1] = { path = "c/" .. path, data = data } end
  table.sort(out, function(a, b) return a.path < b.path end)
  return out
end

function T:test_two_broken_files_give_the_same_error_in_every_order()
  local scenarios = {
    { name = "two page names that Windows refuses", expected = "a?", first = "en/a?.md",
      extra = { ["en/con.md"] = page("C"), ["en/aux.md"] = page("A"), ["en/a?.md"] = page("Q"), ["en/z|.md"] = page("Z") } },
    { name = "two pages that differ only by case", expected = "differ only by case",
      extra = { ["en/Aa.md"] = page("1"), ["en/aA.md"] = page("2"), ["en/Bb.md"] = page("3"), ["en/bB.md"] = page("4") } },
    { name = "two pairs that differ only in normalisation", expected = "normalisation",
      extra = { ["en/caf\u{E9}.md"] = page("1"), ["en/cafe\u{301}.md"] = page("2"), ["en/\u{C5}.md"] = page("3"), ["en/A\u{30A}.md"] = page("4") } },
    { name = "two pages with an unknown audience", expected = "audience",
      extra = { ["en/x1.md"] = page("1", "t", "audience: nobody\n"), ["en/x2.md"] = page("2", "t", "audience: someone\n"),
        ["en/x3.md"] = page("3", "t", "audience: other\n") } },
    { name = "two pages that are not UTF-8", expected = "UTF-8",
      extra = { ["en/u1.md"] = "---\ntitle: a\n---\n\xFF\n", ["en/u2.md"] = "---\ntitle: b\n---\n\xC0\xAF\n", ["en/u3.md"] = "\xED\xA0\x80\n" } },
    { name = "many pages with an unknown audience (the order in which pages are read)", expected = "audience", first = "en/n01.md", extra = (function()
        local extra = {}
        for index = 1, 16 do extra[("en/n%02d.md"):format(index)] = page("N", "t", "audience: nobody" .. index .. "\n") end
        return extra
      end)() },
    { name = "many pairs of pages with one URL (the order in which pages are built)", expected = "same URL", first = "u01", extra = (function()
        local extra = {}
        for index = 1, 16 do
          extra[("en/u%02d.md"):format(index)] = page("U", "t")
          extra[("en/u%02d/index.md"):format(index)] = page("UI", "t")
        end
        return extra
      end)() },
    { name = "many pages that cannot be rendered (the order in which pages are built)", expected = "nests more than", first = "en/d01.md", extra = (function()
        local extra = {}
        for index = 1, 16 do extra[("en/d%02d.md"):format(index)] = page("D", string.rep("> ", 101) .. "x") end
        return extra
      end)() },
    { name = "a broken page in each locale", expected = "UTF-8",
      extra = { ["en/b.md"] = "\xFF\n", ["fr/b.md"] = "\xFE\n" } },
  }
  for _, scenario in ipairs(scenarios) do
    local list = with(base(), scenario.extra)
    local reference = error_of(ordered(list, "sorted"))
    self:assert_not_nil(reference, scenario.name .. ": the build must raise")
    self:assert_true(core.is_instance_of(reference, core.Error), scenario.name .. ": " .. tostring(reference))
    self:assert_true(reference.message:find(scenario.expected, 1, true) ~= nil, scenario.name .. ": " .. reference.message)
    if scenario.first then
      -- Not only the same error in every order: the one of the first file by name (an unsorted walk could be consistently wrong).
      self:assert_true(reference.message:find(scenario.first, 1, true) ~= nil, scenario.name .. ": names " .. scenario.first .. ": " .. reference.message)
    end
    for _, order in ipairs(orders()) do
      local err = error_of(ordered(list, order[1], order[2]))
      self:assert_not_nil(err, scenario.name)
      self:assert_equal(reference.message, err.message, scenario.name .. " in order " .. order[1] .. " " .. tostring(order[2] or ""))
    end
  end
end

return T
