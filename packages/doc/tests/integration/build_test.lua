---@diagnostic disable: need-check-nil  -- tests read files they have just built; a nil fails the assertion that follows
-- Integration: builds the fixture site on the real file system, through the library and
-- through the `bin/build.lua` runner.
local test = require("harness.test")
local doc = require("hecate.doc")
local reactor = require("hecate.reactor")
local core = require("hecate.core")
local T = test.Case("BuildIntegrationTest")

local here = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
local package_dir = here:match("^(.*)/tests/integration/")
local fixture = package_dir .. "/tests/fixtures/site"
local runner = package_dir .. "/bin/build.lua"

local fs = doc.SystemFileSystem()
local is_windows = package.config:sub(1, 1) == "\\"

local function quote(path)
  if is_windows then return '"' .. path:gsub("/", "\\") .. '"' end
  return "'" .. path:gsub("'", "'\\''") .. "'"
end

-- A name that two processes started together cannot share: a counter of this process, the address of a fresh table (it varies
-- between processes) and `math.random`, which Lua seeds randomly at start (a reseed from the clock would make the names of two
-- runs that start in the same second equal).
local counter = 0
local function temporary()
  local base = (os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP") or "/tmp"):gsub("\\", "/"):gsub("/+$", "")
  counter = counter + 1
  return ("%s/hecate-doc-it-%s-%d-%d"):format(base, tostring({}):match("%x+$") or "0", counter, math.random(1, 1e9))
end

local function run(arguments)
  local command = ("%s %s %s"):format(quote(arg[-1] or "lua"), quote(runner), arguments)
  if is_windows then command = '"' .. command .. '"' end
  local pipe = assert(io.popen(command .. " 2>&1", "r"))
  local output = pipe:read("a")
  local ok = pipe:close()
  return output, ok == true
end

local function load_site_configuration()
  return doc.load_site_configuration(fs, fixture .. "/site.lua")
end

function T:test_the_library_builds_the_fixture_site_to_disk()
  local out = temporary()
  local report = doc.build({ site_configuration = load_site_configuration(), guides_dir = fixture, output_dir = out, file_system = fs, clean_output_dir = true })
  local ok, err = pcall(function()
    self:assert_equal(0, #report.problems, table.concat(report.problems, "\n"))
    self:assert_equal(6, report.locales.en.pages)
    self:assert_equal(4, report.locales.fr.fallbacks)
    for _, path in ipairs({
      "/index.html", "/404.html", "/sitemap.xml", "/hello.txt", "/en/index.html", "/en/guide/concurrency/index.html",
      "/en/reference/sleep/index.html", "/fr/guide/concurrency/index.html", "/en/guide/diagram.svg",
      "/assets/theme.css", "/assets/search-fr.json", "/assets/fonts/fira-code-latin-400-normal.woff2",
    }) do
      self:assert_true(fs:exists(out .. path), path)
    end
    local page = fs:read(out .. "/en/guide/concurrency/index.html")
    self:assert_true(page:find("<h2 id=\"callouts\"", 1, true) ~= nil)
    self:assert_true(page:find('class="markdown-alert markdown-alert-caution"', 1, true) ~= nil)
    self:assert_true(page:find('<a href="/en/reference/sleep/#syntax">', 1, true) ~= nil)
    local font = fs:read(out .. "/assets/fonts/fira-code-latin-400-normal.woff2")
    self:assert_equal(fs:read(doc.theme.assets_directory() .. "/fonts/fira-code-latin-400-normal.woff2"), font,
      "binary files are copied byte for byte")
    self:assert_equal("public file\n", fs:read(out .. "/hello.txt"))
    local fallback = fs:read(out .. "/fr/guide/first-example/index.html")
    self:assert_true(fallback:find('class="notice"', 1, true) ~= nil)
  end)
  fs:remove_tree(out)
  if not ok then error(err, 0) end
end

function T:test_two_builds_produce_the_same_files()
  local first, second = temporary(), temporary()
  local function listing(root)
    local out = {}
    local function visit(directory, relative)
      for _, entry in ipairs(fs:list(directory) or {}) do
        local path, child = directory .. "/" .. entry.name, relative .. "/" .. entry.name
        if entry.is_directory then visit(path, child) else out[child] = fs:read(path) end
      end
    end
    visit(root, "")
    return out
  end
  local config = load_site_configuration()
  local ok, err = pcall(function()
    doc.build({ site_configuration = config, guides_dir = fixture, output_dir = first, file_system = fs })
    doc.build({ site_configuration = load_site_configuration(), guides_dir = fixture, output_dir = second, file_system = fs })
    local a, b = listing(first), listing(second)
    local count = 0
    for path, data in pairs(a) do
      count = count + 1
      self:assert_true(b[path] == data, "differs: " .. path)
    end
    for path in pairs(b) do self:assert_not_nil(a[path], "extra: " .. path) end
    self:assert_true(count > 30)
  end)
  fs:remove_tree(first)
  fs:remove_tree(second)
  if not ok then error(err, 0) end
end

function T:test_clean_refuses_an_output_directory_that_is_a_symlink()
  if is_windows then return end
  local uv = require("luv")
  local root = temporary()
  local ok, err = pcall(function()
    doc.build({ site_configuration = load_site_configuration(), guides_dir = fixture, output_dir = root .. "/real", file_system = fs, clean_output_dir = true })
    assert(uv.fs_symlink(root .. "/real", root .. "/link"))
    local failure = self:assert_error(function()
      doc.build({ site_configuration = load_site_configuration(), guides_dir = fixture, output_dir = root .. "/link", file_system = fs, clean_output_dir = true })
    end)
    self:assert_true(core.is_instance_of(failure, doc.BuildError), tostring(failure))
    self:assert_true(tostring(failure):find("symbolic link", 1, true) ~= nil, tostring(failure))
    self:assert_true(fs:exists(root .. "/real/en/index.html"), "the target was not cleaned")
  end)
  fs:remove_tree(root)
  if not ok then error(err, 0) end
end

function T:test_the_runner_builds_a_site_and_reports()
  local out = temporary()
  local output, ok = run(("%s --out %s --strict --no-git-dates --clean"):format(quote(fixture), quote(out)))
  local built = fs:exists(out .. "/en/index.html")
  local sitemap = fs:read(out .. "/sitemap.xml")
  fs:remove_tree(out)
  self:assert_true(ok, output)
  self:assert_true(output:find("hecate.doc: %d+ files, %d+ bytes; en: 6 pages %(0 from the default locale%); fr: 6 pages %(4 from the default locale%)") ~= nil, output)
  self:assert_true(built)
  self:assert_true(sitemap:find("https://docs.example.test/en/guide/concurrency/", 1, true) ~= nil)
end

function T:test_the_runner_refuses_malformed_command_lines_with_a_usage_error()
  local cases = {
    { "--bogus", "unknown option --bogus" },
    { "-x", "unknown option -x" },
    { "--strict=yes", "takes no value" },
    { "--out", "needs a value" },
    { "--out --strict", "needs a value" },
    { "--base", "needs a value" },
    { "--strict --strict", "repeated option --strict" },
    { "--out a --out b", "repeated option --out" },
    { "--base /a/ --base=/b/", "repeated option --base" },
    { "one two", "more than one source directory" },
    { "--base //evil.test/", "invalid --base" },
    { "--url " .. quote("javascript:alert(1)"), "invalid --url" },
  }
  for _, case in ipairs(cases) do
    local output, ok = run(case[1] .. " --no-git-dates")
    self:assert_false(ok, case[1])
    self:assert_true(output:find(case[2], 1, true) ~= nil, case[1] .. ": " .. output)
    self:assert_true(output:find("usage:", 1, true) ~= nil, case[1] .. ": " .. output)
  end
  local output, ok = run("--help")
  self:assert_true(ok, output)
  self:assert_true(output:find("usage:", 1, true) ~= nil)
end

function T:test_the_runner_accepts_values_with_an_equals_sign()
  local out = temporary()
  local output, ok = run(("%s --out=%s --base=/docs --no-git-dates"):format(quote(fixture), quote(out)))
  local page = fs:read(out .. "/en/guide/concurrency/index.html")
  fs:remove_tree(out)
  self:assert_true(ok, output)
  self:assert_true(page:find('href="/docs/assets/theme.css"', 1, true) ~= nil)
end

function T:test_the_runner_applies_a_base_path()
  local out = temporary()
  local output, ok = run(("%s --out %s --base /docs/"):format(quote(fixture), quote(out)))
  local page = fs:read(out .. "/en/guide/concurrency/index.html")
  fs:remove_tree(out)
  self:assert_true(ok, output)
  self:assert_true(page:find('href="/docs/assets/theme.css"', 1, true) ~= nil)
end

function T:test_the_runner_fails_on_a_missing_source_and_on_strict_problems()
  local out = temporary()
  local output, ok = run(("%s --out %s"):format(quote(package_dir .. "/tests/fixtures/nowhere"), quote(out)))
  self:assert_false(ok)
  self:assert_true(output:find("cannot read site configuration", 1, true) ~= nil, output)
  local _, unknown = run("--frobnicate")
  self:assert_false(unknown)
  fs:remove_tree(out)
end

function T:test_the_runner_in_strict_mode_fails_once_for_every_problem_including_the_reference()
  local root = temporary()
  local ok, err = pcall(function()
    fs:write(root .. "/en/index.md", "# Home\n\n[broken](missing.md)\n")
    fs:write(root .. "/site.lua", 'return { title = "T" }\n')
    local lenient, lenient_ok = run(("%s --out %s/out --reference --root %s --packages nopackage"):format(quote(root), root, quote(root)))
    self:assert_true(lenient_ok, lenient)
    self:assert_true(lenient:find("broken link", 1, true) ~= nil, lenient)
    local output, strict_ok = run(("%s --out %s/out2 --strict --reference --root %s --packages nopackage"):format(quote(root), root, quote(root)))
    self:assert_false(strict_ok, output)
    self:assert_true(output:find("broken link", 1, true) ~= nil, output)
    -- The problem of the reference is in the same error: no package, or no LuaLS to read it with.
    self:assert_true(output:find("nopackage", 1, true) ~= nil or output:find("lua-language-server", 1, true) ~= nil, output)
    self:assert_true(fs:exists(root .. "/out2/en/index.html"), "the site was written before the error")
  end)
  fs:remove_tree(root)
  if not ok then error(err, 0) end
end

function T:test_a_link_in_the_content_tree_is_not_followed_on_the_real_file_system()
  if is_windows then return end
  local uv = require("luv")
  local root = temporary()
  local ok, err = pcall(function()
    fs:write(root .. "/c/en/index.md", "# Home\n")
    fs:write(root .. "/outside/id_rsa", "SSH-KEY-CANARY")
    fs:write(root .. "/outside/page.md", "# Out\n\nOUTSIDE-CANARY\n")
    fs:write(root .. "/c/public/ok.txt", "fine")
    assert(uv.fs_symlink(root .. "/outside/id_rsa", root .. "/c/public/id_rsa"))
    assert(uv.fs_symlink(root .. "/outside/id_rsa", root .. "/c/en/key.txt"))
    assert(uv.fs_symlink(root .. "/outside", root .. "/c/en/outside"))
    assert(uv.fs_symlink(root .. "/c", root .. "/c/en/up"))
    local report = doc.build({ site_configuration = { title = "T" }, guides_dir = root .. "/c", output_dir = root .. "/o", file_system = fs })
    self:assert_equal("fine", fs:read(root .. "/o/ok.txt"))
    self:assert_nil(fs:read(root .. "/o/id_rsa"))
    self:assert_nil(fs:read(root .. "/o/en/key.txt"))
    self:assert_false(fs:exists(root .. "/o/en/outside"))
    local linked = 0
    for _, problem in ipairs(report.problems) do
      if problem:find("symbolic link", 1, true) then linked = linked + 1 end
    end
    self:assert_equal(4, linked, table.concat(report.problems, "\n"))
    local failure = self:assert_error(function()
      doc.build({ site_configuration = { title = "T" }, guides_dir = root .. "/c", output_dir = root .. "/o", file_system = fs,
        fail_on_problems = true })
    end)
    self:assert_true(core.is_instance_of(failure, doc.BuildError), tostring(failure))
  end)
  fs:remove_tree(root)
  if not ok then error(err, 0) end
end

function T:test_a_generated_page_is_not_written_through_a_dangling_link_on_the_real_file_system()
  if is_windows then return end
  local uv = require("luv")
  local root = temporary()
  local ok, err = pcall(function()
    fs:write(root .. "/docs/maintainer/en/index.md", "# Home\n")
    assert(uv.fs_symlink(root .. "/victim.txt", root .. "/docs/maintainer/en/configuration.md"))
    local failure = self:assert_error(function()
      doc.generate_project_documentation({ project_dir = root, site_configuration = { title = "T" },
        application = { configuration_schema = function() return { type = "object", properties = { a = { type = "string" } } } end },
        file_system = fs })
    end)
    self:assert_true(core.is_instance_of(failure, doc.BuildError), tostring(failure))
    self:assert_false(fs:exists(root .. "/victim.txt"), "the target of the link was not created")
    -- A build whose output has a link at the place of an output file is refused the same way.
    fs:write(root .. "/c/en/index.md", "# Home\n")
    fs:write(root .. "/victim2.txt", "VICTIM")
    assert(uv.fs_mkdir(root .. "/o", 493))
    assert(uv.fs_mkdir(root .. "/o/en", 493))
    assert(uv.fs_symlink(root .. "/victim2.txt", root .. "/o/en/index.html"))
    local second = self:assert_error(function()
      doc.build({ site_configuration = { title = "T" }, guides_dir = root .. "/c", output_dir = root .. "/o", file_system = fs })
    end)
    self:assert_true(core.is_instance_of(second, doc.BuildError), tostring(second))
    self:assert_equal("VICTIM", fs:read(root .. "/victim2.txt"))
  end)
  fs:remove_tree(root)
  if not ok then error(err, 0) end
end

function T:test_building_the_repository_website_has_no_problem()
  local website = package_dir .. "/../../website"
  if not fs:exists(website .. "/site.lua") then return end
  -- Two sites, one per tree (OQ-144): each tree is built from its own content root with the one `site.lua`.
  local code_reference = require("hecate.doc.reference_site")
  for _, tree in ipairs({ "user", "maintainer" }) do
    local root = website .. "/" .. tree
    local out = temporary()
    local configuration = doc.load_site_configuration(fs, website .. "/site.lua")
    if configuration.edit_link_template then
      configuration.edit_link_template = configuration.edit_link_template:gsub("{tree}", tree)
    end
    local report = doc.build({
      site_configuration = configuration, guides_dir = root, output_dir = out, file_system = fs, fail_on_problems = false,
    })
    fs:remove_tree(out)
    -- The code reference (website/<tree>/en/reference/<package>/) is generated and not in a clean checkout, so
    -- the guides' links into it cannot resolve there; `website.yml` builds with --strict after generating
    -- it. A link into a package whose reference is not generated is not a problem of this test; any
    -- other problem is, and so is a link into a generated reference that does not resolve.
    local generated = {}
    for _, name in ipairs(code_reference.DEFAULT_PACKAGES) do
      generated[name] = fs:exists(root .. "/en/reference/" .. name .. "/index.md")
    end
    -- The same for the architecture specifications and the ADRs of the maintainer tree (`gen-maintainer-docs`).
    for _, directory in ipairs({ "architecture", "adr" }) do
      generated[directory] = fs:exists(root .. "/en/" .. directory .. "/index.md")
    end
    -- The same for the two pages of `gen-error-codes` and `gen-config-reference`, generated by `website.yml`.
    local generated_pages = {}
    for _, page in ipairs({ "error-codes.md", "configuration-keys.md" }) do
      generated_pages[page] = fs:exists(root .. "/en/reference/" .. page)
    end
    local problems = {}
    for _, problem in ipairs(report.problems) do
      local target = problem:match("broken link (.+)$")
      local name = target and (target:match("reference/([%w_]+)/") or target:match("^([%w_]+)/"))
      local page = target and target:match("([%w%-]+%.md)$")
      local absent_page = page ~= nil and generated_pages[page] == false
      if not ((name and generated[name] == false) or absent_page) then problems[#problems + 1] = problem end
    end
    self:assert_equal(0, #problems, tree .. ":\n" .. table.concat(problems, "\n"))
    self:assert_true(report.locales.en.pages >= 2, tree .. " has its pages")
  end
end

-- `SystemFileSystem` suspends: every test of this file runs inside a reactor.
for name, method in pairs(T) do
  if type(name) == "string" and name:find("^test_") and type(method) == "function" then
    T[name] = function(...) return reactor.run(method, ...) end
  end
end

return T
