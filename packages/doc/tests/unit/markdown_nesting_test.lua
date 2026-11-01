-- Pathological nesting: a native stack overflow cannot be caught, so a document must either render
-- or be refused with a clean error, quickly, and never take the process down. The risky inputs run
-- in a child interpreter so that a crash is a failed assertion, not a dead test runner.
local test = require("harness.test")
local markdown = require("hecate.doc.markdown")
local core = require("hecate.core")
local T = test.Case("MarkdownNestingTest")

local function has(text, part) return text:find(part, 1, true) ~= nil end

local LIMIT = 100 -- block nesting limit documented in the README (native MAX_NESTING)

local PRELUDE = ("package.path = %q; package.cpath = %q; local markdown = require('hecate.doc.markdown');")
  :format(package.path, package.cpath)

-- Runs `build` (Lua source returning the document) in a child interpreter; returns the status
-- printed by the child ("ok", "refused") or "crash:..." when the process died.
local function child(build)
  if package.config:sub(1, 1) == "\\" then
    -- Windows: the launch of a child interpreter through `cmd` is not portable here. The inputs run in this process:
    -- a native crash would then fail the whole run loudly instead of one assertion.
    local source = assert(load("return (function() " .. build .. " end)()"))()
    local ok, err = pcall(markdown.render, source)
    if ok then return "ok" end
    if core.is_instance_of(err, core.Error) then return "refused" end
    return "error:" .. tostring(err)
  end
  local script = PRELUDE .. "local source = (function() " .. build .. " end)()\n" .. [[
    local ok, err = pcall(markdown.render, source)
    if ok then io.write("ok")
    elseif type(err) == "table" and err.message then io.write("refused")
    else io.write("error:" .. tostring(err)) end
  ]]
  local file = os.tmpname()
  local handle = assert(io.open(file, "wb"))
  handle:write(script)
  handle:close()
  local pipe = assert(io.popen(('"%s" "%s" 2>&1'):format(arg[-1] or "lua", file), "r"))
  local output = pipe:read("a")
  local ok, how, code = pipe:close()
  os.remove(file)
  if not ok then return "crash:" .. tostring(how) .. ":" .. tostring(code) end
  return output
end

local function assert_survives(self, build, expected)
  local started = os.time()
  local clock = os.clock()
  local status = child(build)
  self:assert_true(status == "ok" or status == "refused", "unexpected child status: " .. status)
  if expected then self:assert_equal(expected, status) end
  -- The child's time is wall time here (os.clock counts only this process), so use both.
  self:assert_true(os.time() - started < 8 and os.clock() - clock < 8, "took too long")
end

function T:test_deep_blockquote_nesting_is_refused()
  assert_survives(self, [[return string.rep(">", 200000) .. " x\n"]], "refused")
end

function T:test_deep_list_nesting_is_refused()
  assert_survives(self, [[return string.rep("- ", 200000) .. "x\n"]], "refused")
  assert_survives(self, [[return string.rep("1. ", 200000) .. "x\n"]], "refused")
  assert_survives(self, [[return string.rep(">- ", 100000) .. "x\n"]], "refused")
end

function T:test_the_refusal_is_an_argument_error_naming_the_line()
  local ok, err = pcall(markdown.render, "fine\n\n" .. string.rep("> ", LIMIT + 1) .. "x\n")
  self:assert_true(not ok)
  self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
  self:assert_true(has(tostring(err), "line 3"), tostring(err))
end

function T:test_deep_inline_nesting_survives()
  assert_survives(self, [[return string.rep("[", 100000)]])
  assert_survives(self, [[return string.rep("*a ", 100000)]])
  assert_survives(self, [[return string.rep("*a _a ", 100000) .. string.rep("a_ a* ", 100000)]], "ok")
  assert_survives(self, [[return string.rep("![a ", 50000) .. string.rep("](x) ", 50000)]], "ok")
  assert_survives(self, [[return string.rep("*", 200000) .. "a" .. string.rep("*", 200000)]])
end

function T:test_many_delimiters_survive()
  assert_survives(self, [[return string.rep("*_", 100000)]])
  assert_survives(self, [[return string.rep("`a", 100000)]])
  assert_survives(self, [[return string.rep("[a](", 50000)]])
  assert_survives(self, [[return string.rep("<", 100000)]])
  assert_survives(self, [[return string.rep("|a", 50000) .. "\n"]])
end

function T:test_realistic_nesting_renders_up_to_depth_20()
  for depth = 1, 20 do
    local quote = markdown.render(string.rep("> ", depth) .. "text\n")
    self:assert_equal(depth, select(2, quote.html:gsub("<blockquote>", "")))
    local lines = {}
    for level = 1, depth do lines[#lines + 1] = string.rep("  ", level - 1) .. "- item " .. level end
    local list = markdown.render(table.concat(lines, "\n") .. "\n")
    self:assert_equal(depth, select(2, list.html:gsub("<ul>", "")))
  end
  local mixed = markdown.render("> - one\n>   > - two\n>   >   1. three\n")
  self:assert_true(has(mixed.html, "three"))
end

function T:test_the_limit_is_exact_and_ignores_text()
  self:assert_true(has(markdown.render(string.rep(">", LIMIT) .. " x\n").html, "x"))
  self:assert_true(not pcall(markdown.render, string.rep(">", LIMIT + 1) .. " x\n"))
  -- Characters that are not block markers in leading position do not count.
  self:assert_true(has(markdown.render("a " .. string.rep("> ", 500) .. "b\n").html, "b"))
  self:assert_true(has(markdown.render("1 - " .. string.rep("- ", 500) .. "b\n").html, "b"))
end

return T
