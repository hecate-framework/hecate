---@diagnostic disable: need-check-nil  -- tests read files they have just generated; a nil fails the assertion that follows
-- Integration: the LuaLS export format (pinned: a fresh export of the fixture package equals the
-- checked-in one), and the runners that write the reference pages and build the site with them.
-- The tests that need `lua-language-server` do nothing when it is not installed locally; in CI (`CI` set) they
-- fail instead, because the workflow installs it on every platform (`lua tools/run.lua setup-luals`).
local test = require("harness.test")
local doc = require("hecate.doc")
local reactor = require("hecate.reactor")
local luals = require("hecate.doc.luals")
local reference_site = require("hecate.doc.reference_site")
local json = require("hecate.json")
local T = test.Case("ReferenceIntegrationTest")

local here = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
local package_dir = here:match("^(.*)/tests/integration/")
local fixtures = package_dir .. "/tests/fixtures/reference"
local root = fixtures .. "/root"
local fs = doc.SystemFileSystem()
local is_windows = package.config:sub(1, 1) == "\\"
local executable = luals.locate()

--- True when the test cannot run for lack of LuaLS: skipped locally, a failure in CI.
local function lacks_language_server(case)
  if executable then return false end
  if os.getenv("CI") then case:fail("lua-language-server is not installed (CI installs it: lua tools/run.lua setup-luals)") end
  return true
end

local function quote(path)
  if is_windows then return '"' .. path:gsub("/", "\\") .. '"' end
  return "'" .. path:gsub("'", "'\\''") .. "'"
end

local function temporary()
  local base = (os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP") or "/tmp"):gsub("\\", "/"):gsub("/+$", "")
  math.randomseed(os.time() + math.floor(os.clock() * 1e6))
  return ("%s/hecate-doc-reference-%d"):format(base, math.random(1, 1e9))
end

local function run(script, arguments)
  local command = ("%s %s %s"):format(quote(arg[-1] or "lua"), quote(package_dir .. "/bin/" .. script), arguments)
  if is_windows then command = '"' .. command .. '"' end
  local pipe = assert(io.popen(command .. " 2>&1", "r"))
  local output = pipe:read("a")
  local ok = pipe:close()
  return output, ok == true
end

function T:test_a_fresh_export_of_the_fixture_package_equals_the_checked_in_export()
  if lacks_language_server(self) then return end
  local language_server = assert(executable)
  self:assert_equal(luals.PINNED, luals.version(language_server),
    "the fixture export and the generator are written for the pinned LuaLS")
  local source = root .. "/packages/demo/src"
  local fresh = luals.export(language_server, source, { file_system = fs, language_server_config_path = package_dir .. "/../../.luarc.json" })
  -- The export holds absolute paths (the `DOC` key, and the `file://` links of `---@see`).
  local function normalise(text)
    text = text:gsub('file://[^)"]*', "file://<DOC>")
    text = text:gsub('"DOC":%s*"[^"]*"', '"DOC": "<DOC>"')
    -- On Windows LuaLS also exports the built-in library definitions; the pinned export is
    -- the documented package only (the reference renderer ignores the rest).
    local kept = {}
    for _, entry in ipairs(json.decode(text)) do
      if entry.type == "luals.config" or (entry.name or ""):find("^hecate%.") then kept[#kept + 1] = entry end
    end
    return json.encode(kept)
  end
  self:assert_equal(normalise(fs:read(fixtures .. "/export.json")), normalise(fresh))
end

function T:test_the_runner_writes_the_golden_pages()
  if lacks_language_server(self) then return end
  local out = temporary()
  local output, ok = run("reference.lua", ("--root %s --out %s --packages demo"):format(quote(root), quote(out)))
  local done, err = pcall(function()
    self:assert_true(ok, output)
    self:assert_true(output:find("8 reference pages for demo", 1, true) ~= nil, output)
    for _, path in ipairs({ "index.md", "Counter.md", "CounterError.md", "CounterOptions.md", "functions/add.md",
      "functions/name.md", "functions/undocumented.md", "functions/wait.md" }) do
      local expected = fs:read(fixtures .. "/golden/reference/demo/" .. path)
      self:assert_equal(expected, fs:read(out .. "/reference/demo/" .. path), path)
    end
  end)
  fs:remove_tree(out)
  if not done then error(err, 0) end
end

function T:test_the_runner_leaves_a_directory_with_hand_written_pages_alone()
  if lacks_language_server(self) then return end
  local out = temporary()
  fs:write(out .. "/reference/demo/mine.md", "# Written by hand\n")
  local output, ok = run("reference.lua", ("--root %s --out %s --packages demo"):format(quote(root), quote(out)))
  local done, err = pcall(function()
    self:assert_true(ok, output)
    self:assert_true(output:find("not generated", 1, true) ~= nil, output)
    self:assert_equal("# Written by hand\n", fs:read(out .. "/reference/demo/mine.md"))
    self:assert_nil(fs:read(out .. "/reference/demo/index.md"))
  end)
  fs:remove_tree(out)
  if not done then error(err, 0) end
end

function T:test_without_lua_language_server_nothing_is_written_and_the_skip_is_reported()
  local original = luals.locate
  ---@diagnostic disable-next-line: duplicate-set-field  -- replaced for the test, restored below
  luals.locate = function() return nil end
  local memory = doc.MemoryFileSystem()
  local ok, report = pcall(reference_site.run, { project_dir = root, locale_dir = "en", file_system = memory })
  ---@diagnostic disable-next-line: duplicate-set-field
  luals.locate = original
  self:assert_true(ok, tostring(report))
  self:assert_true(report.skipped ~= nil and report.skipped:find("lua-language-server", 1, true) ~= nil)
  self:assert_equal(0, report.pages)
  self:assert_nil(memory:list("en"))
end

function T:test_the_site_builder_runs_the_generator_first_with_the_reference_flag()
  if lacks_language_server(self) then return end
  local site = temporary()
  fs:write(site .. "/site.lua", "return { title = 'demo', top_links = { { text = 'Reference', link = 'reference/' } } }")
  fs:write(site .. "/en/index.md", "---\ntitle: Home\n---\n\n# Home\n\n[Demo](reference/demo/index.md)\n")
  local output, ok = run("build.lua", ("%s --reference --root %s --packages demo --strict --no-git-dates"):format(
    quote(site), quote(root)))
  local done, err = pcall(function()
    self:assert_true(ok, output)
    self:assert_true(fs:exists(site .. "/en/reference/demo/functions/add.md"))
    self:assert_true(fs:exists(site .. "/dist/en/reference/demo/functions/add/index.html"))
    self:assert_true(fs:exists(site .. "/dist/en/reference/demo/Counter/index.html"))
  end)
  fs:remove_tree(site)
  if not done then error(err, 0) end
end

-- OQ-142: with no `language_server_config_path` no `--configpath` is passed to LuaLS, and with one it is passed as given.
function T:test_the_language_server_gets_a_config_path_only_when_one_is_given()
  if package.config:sub(1, 1) == "\\" then return end
  local directory = temporary()
  local ok, err = pcall(function()
    local log = directory .. "/arguments.log"
    fs:write(directory .. "/fake-luals", ([[#!/bin/sh
echo "$@" >> '%s'
case "$1" in --version) echo "%s"; exit 0;; esac
for argument in "$@"; do case "$argument" in --doc_out_path=*) out="${argument#--doc_out_path=}";; esac; done
echo '[]' > "$out/doc.json"
]]):format(log, luals.PINNED))
    assert(os.execute("chmod +x '" .. directory .. "/fake-luals'"))
    fs:write(directory .. "/project/packages/demo/src/x.lua", "return {}")
    local function arguments_of(extra)
      fs:write(log, "")
      local options = { project_dir = directory .. "/project", locale_dir = directory .. "/en", file_system = fs,
        packages = { "demo" }, language_server_path = directory .. "/fake-luals" }
      for key, value in pairs(extra or {}) do options[key] = value end
      local report = reference_site.run(options)
      self:assert_nil(report.skipped)
      return fs:read(log)
    end
    self:assert_nil(arguments_of():find("--configpath", 1, true), "none by default")
    local given = arguments_of({ language_server_config_path = directory .. "/project/custom.json" })
    self:assert_not_nil(given:find("--configpath=", 1, true), given)
    self:assert_not_nil(given:find("custom.json", 1, true), given)
  end)
  fs:remove_tree(directory)
  if not ok then error(err, 0) end
end

-- `SystemFileSystem` suspends: every test of this file runs inside a reactor.
for name, method in pairs(T) do
  if type(name) == "string" and name:find("^test_") and type(method) == "function" then
    T[name] = function(...) return reactor.run(method, ...) end
  end
end

return T
