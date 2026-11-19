---@diagnostic disable: need-check-nil  -- tests index results that a failing assertion would reveal
-- The rockspec of an installed rock is data of the project: read, never run. The reader is total (it returns a rock or
-- a problem, it never raises), bounded in time and memory, and refuses every construct that computes.
local test = require("harness.test")
local doc = require("hecate.doc")
local core = require("hecate.core")
local licences = require("hecate.doc.licences")
local sandbox = require("hecate.doc.internal.sandbox")
local T = test.Case("RockspecHardeningTest")

local HEAD = 'package = "a"\nversion = "1-1"\n'
local MAX_BYTES = 256 * 1024

local function refused(self, text, label)
  local ok, rock, problem = pcall(licences.parse_rockspec, text)
  self:assert_true(ok, (label or "") .. ": raised " .. tostring(rock))
  self:assert_nil(rock, label)
  self:assert_equal("string", type(problem), label)
  return problem
end

function T:test_the_doubling_rockspec_is_refused_without_allocating()
  -- 298 bytes of text that, run, built a string of 14 MiB: each line doubles the one before.
  local lines = { HEAD, 'local a = "xxxxxxxx"\n' }
  for index = 1, 22 do lines[#lines + 1] = ("local b%d = a .. a\n"):format(index) end
  lines[#lines + 1] = 'local a = "xxxxxxxx" local b = a..a local c = b..b local d = c..c\n'
  local text = table.concat(lines)
  collectgarbage()
  local before = collectgarbage("count")
  local problem = refused(self, text)
  self:assert_not_nil(problem:find("..", 1, true), problem)
  self:assert_true(collectgarbage("count") - before < 1024, "the text was not evaluated")
end

function T:test_concatenation_is_refused_outside_strings_only()
  refused(self, HEAD .. 'x = "a" .. "b"\n', "..")
  refused(self, HEAD .. "x = 1 ..2\n", "number")
  refused(self, HEAD .. "x = ...\n", "vararg")
  local rock = licences.parse_rockspec(HEAD .. 'description = { license = "MIT..", homepage = [[a .. b]] } -- x .. y\n')
  self:assert_equal("MIT..", rock.licence)
end

function T:test_calls_without_parentheses_are_refused()
  for _, text in ipairs({ 'os.execute"x"', 'f{}', 'f[[x]]', 'f"x"', "f'x'", 'os.execute [==[x]==]', 'x = f{ 1 }', 'x = a.b "c"',
    'x = {}{}', 'x = a[1]"c"', 'x = ("y")', 'x:y()' }) do
    refused(self, HEAD .. text .. "\n", text)
  end
  -- Names before a string or a table that are keywords of expressions are not calls.
  local rock = licences.parse_rockspec(HEAD .. 'y = true and "x" or {}\nz = not nil and { "a" }\n')
  self:assert_equal("a", rock.name)
end

function T:test_deep_nesting_is_a_problem_and_never_an_error()
  local deep = HEAD .. "x = " .. ("{"):rep(100000) .. ("}"):rep(100000) .. "\n"
  refused(self, deep, "100000 levels")
  refused(self, HEAD .. "x = " .. ("{"):rep(300) .. ("}"):rep(300) .. "\n", "300 levels")
  local moderate = licences.parse_rockspec(HEAD .. "x = " .. ("{"):rep(50) .. ("}"):rep(50) .. "\n")
  self:assert_equal("a", moderate.name)
  refused(self, HEAD .. "x = " .. ("{"):rep(1000), "unterminated")
  refused(self, HEAD .. "x = " .. ("-"):rep(100000) .. "1\n", "comment")
end

function T:test_the_size_cap_is_exact()
  local padding = MAX_BYTES - #HEAD
  local exact = HEAD .. (" "):rep(padding)
  self:assert_equal(MAX_BYTES, #exact)
  self:assert_equal("a", licences.parse_rockspec(exact).name, "a text of exactly the cap is read")
  local problem = refused(self, exact .. " ", "one byte more")
  self:assert_not_nil(problem:find(tostring(MAX_BYTES), 1, true), problem)
  refused(self, 42, "not text")
  refused(self, nil, "nil")
end

function T:test_the_instruction_hook_ends_what_the_text_checks_miss()
  local ok, message = sandbox.run(function() while true do end end, { instructions = 10000 })
  self:assert_false(ok)
  self:assert_equal("instruction limit", message)
end

function T:test_the_memory_hook_ends_a_runaway_allocation()
  local ok, message = sandbox.run(function()
    local held = {}
    for index = 1, 100000000 do held[index] = { index, index } end
    return held
  end, { kilobytes = 2048, instructions = 1000000000 })
  self:assert_false(ok)
  self:assert_equal("memory limit", message)
end

function T:test_the_sandbox_returns_values_and_errors()
  local ok, value = sandbox.run(function() return { 1, 2 } end)
  self:assert_true(ok)
  self:assert_equal(2, value[2])
  ok, value = sandbox.run(function() error("boom", 0) end)
  self:assert_false(ok)
  self:assert_equal("boom", value)
  ok, value = sandbox.run(function() error({}) end)
  self:assert_false(ok)
  self:assert_equal("string", type(value))
end

function T:test_the_site_configuration_runs_under_the_same_hook()
  local fs = doc.MemoryFileSystem({ ["loop.lua"] = "while true do end", ["grow.lua"] = "local t = {} for i = 1, 1e9 do t[i] = {i} end return t",
    ["fine.lua"] = 'return { title = "T" }' })
  for _, name in ipairs({ "loop.lua", "grow.lua" }) do
    local err = self:assert_error(function() doc.load_site_configuration(fs, name) end)
    self:assert_true(core.is_instance_of(err, core.ConfigurationError), name .. ": " .. tostring(err))
  end
  self:assert_equal("T", doc.load_site_configuration(fs, "fine.lua").title)
end

-- A seeded property test: the reader is total whatever the text. -------------------------------------------------------

local PIECES = { 'package = "a"\n', 'version = "1-1"\n', 'description = { license = "MIT" }\n', 'dependencies = { "lua >= 5.4" }\n',
  "{", "}", "(", ")", "[[", "]]", "[=[", "]=]", "--", "--[[", '"', "'", "\\", "..", "...", "=", ":", ".", ",", ";", "\n", " ", "x",
  "return", "function", "end", "goto", "::l::", "1e9", "0x", "nil", "true", "load", "os", "f", "\0", "\255", "\u{301}", "%", "#" }

local function random_text(random)
  local parts = {}
  for _ = 1, random(1, 40) do parts[#parts + 1] = PIECES[random(1, #PIECES)] end
  return table.concat(parts)
end

function T:test_parse_rockspec_never_raises_and_returns_a_rock_or_a_problem()
  math.randomseed(20261119)
  local valid, refused_count = 0, 0
  for case = 1, 3000 do
    local text = random_text(math.random)
    if case % 3 == 0 then text = HEAD .. text end
    local ok, rock, problem = pcall(licences.parse_rockspec, text)
    self:assert_true(ok, ("case %d raised: %s\n%q"):format(case, tostring(rock), text))
    if rock ~= nil then
      valid = valid + 1
      self:assert_equal("table", type(rock), text)
      self:assert_equal("string", type(rock.name))
      self:assert_equal("string", type(rock.version))
      self:assert_nil(problem)
    else
      refused_count = refused_count + 1
      self:assert_equal("string", type(problem), ("%q"):format(text))
    end
  end
  self:assert_true(valid > 0 and refused_count > 0, "the generator reaches both outcomes")
end

function T:test_front_matter_parse_returns_a_table_or_raises_a_build_error()
  local front_matter = require("hecate.doc.front_matter")
  local lines = { "---", "title: x", "title: y", "a: [1, 2", "b: \"q", "c: 'z'", "- item", "# note", "  - nested", "key:", "d: ]", "e: \\n",
    "...", "---", "x", "", "é", "\255" }
  math.randomseed(20261119)
  local parsed, failed = 0, 0
  for case = 1, 3000 do
    local text = {}
    if case % 4 ~= 0 then text[1] = "---" end
    for _ = 1, math.random(0, 8) do text[#text + 1] = lines[math.random(1, #lines)] end
    if case % 5 ~= 0 then text[#text + 1] = "---" end
    local source = table.concat(text, case % 7 == 0 and "\r\n" or "\n")
    local ok, meta, body = pcall(front_matter.parse, source, "p.md")
    if ok then
      parsed = parsed + 1
      self:assert_equal("table", type(meta), source)
      self:assert_equal("string", type(body), source)
    else
      failed = failed + 1
      self:assert_true(core.is_instance_of(meta, doc.BuildError), ("case %d: %s\n%q"):format(case, tostring(meta), source))
    end
  end
  self:assert_true(parsed > 0 and failed > 0, "the generator reaches both outcomes")
end

return T
