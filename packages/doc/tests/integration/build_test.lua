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

local function temporary()
  local base = (os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP") or "/tmp"):gsub("\\", "/"):gsub("/+$", "")
  math.randomseed(os.time() + math.floor(os.clock() * 1e6))
  return ("%s/hecate-doc-it-%d"):format(base, math.random(1, 1e9))
end

local function run(arguments)
  local command = ("%s %s %s"):format(quote(arg[-1] or "lua"), quote(runner), arguments)
  if is_windows then command = '"' .. command .. '"' end
  local pipe = assert(io.popen(command .. " 2>&1", "r"))
  local output = pipe:read("a")
  local ok = pipe:close()
  return output, ok == true
end

local function load_config()
  return doc.load_config(fixture .. "/site.lua", fs)
end

function T:test_the_library_builds_the_fixture_site_to_disk()
  local out = temporary()
  local report = doc.build({ config = load_config(), source = fixture, out = out, fs = fs, clean = true })
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
  local config = load_config()
  local ok, err = pcall(function()
    doc.build({ config = config, source = fixture, out = first, fs = fs })
    doc.build({ config = load_config(), source = fixture, out = second, fs = fs })
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

function T:test_building_the_repository_website_has_no_problem()
  local website = package_dir .. "/../../website"
  if not fs:exists(website .. "/site.lua") then return end
  local out = temporary()
  local report = doc.build({
    config = doc.load_config(website .. "/site.lua", fs), source = website, out = out, fs = fs, strict = false,
  })
  fs:remove_tree(out)
  -- The code reference (website/en/reference/<package>/) is generated and not in a clean checkout, so
  -- the guides' links into it cannot resolve there; `website.yml` builds with --strict after generating
  -- it. A link into a package whose reference is not generated is not a problem of this test; any
  -- other problem is, and so is a link into a generated reference that does not resolve.
  local generated = {}
  for _, name in ipairs(require("hecate.doc.reference_site").DEFAULT_PACKAGES) do
    generated[name] = fs:exists(website .. "/en/reference/" .. name .. "/index.md")
  end
  local problems = {}
  for _, problem in ipairs(report.problems) do
    local target = problem:match("broken link (.+)$")
    local name = target and (target:match("reference/([%w_]+)/") or target:match("^([%w_]+)/"))
    if not (name and generated[name] == false) then problems[#problems + 1] = problem end
  end
  self:assert_equal(0, #problems, table.concat(problems, "\n"))
  self:assert_true(report.locales.en.pages >= 2)
end

-- `SystemFileSystem` suspends: every test of this file runs inside a reactor.
for name, method in pairs(T) do
  if type(name) == "string" and name:find("^test_") and type(method) == "function" then
    T[name] = function(...) return reactor.run(method, ...) end
  end
end

return T
