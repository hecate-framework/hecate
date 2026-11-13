local test = require("harness.test")
local generated_page = require("lib.generated_page")
local T = test.Case("GeneratedPageTest")

local function is_generated(content) return content:find("<!-- generated -->", 1, true) ~= nil end

local function scratch()
  local path = os.tmpname()
  os.remove(path)
  return ((path .. ".md"):gsub("\\", "/"))
end

local function write(path, content)
  local f = assert(io.open(path, "wb"))
  f:write(content)
  f:close()
end

function T:test_arguments()
  local options = assert(generated_page.arguments({ "--check", "--out", "x.md" }, "gen-x", "default.md"))
  self:assert_true(options.check)
  self:assert_equal("x.md", options.out)
  self:assert_equal("default.md", assert(generated_page.arguments({}, "gen-x", "default.md")).out)
  local none, usage = generated_page.arguments({ "--nope" }, "gen-x", "default.md")
  self:assert_nil(none)
  self:assert_true(assert(usage):find("usage: gen-x", 1, true) ~= nil)
end

function T:test_write_then_check()
  local path = scratch()
  local options = { check = true, task = "gen-x", is_generated = is_generated }
  local state, problems = generated_page.apply(path, "x.md", "<!-- generated -->\na\n", options)
  self:assert_equal("absent", state)
  self:assert_equal(0, #problems)
  options.check = false
  self:assert_equal("written", (generated_page.apply(path, "x.md", "<!-- generated -->\na\n", options)))
  self:assert_equal("unchanged", (generated_page.apply(path, "x.md", "<!-- generated -->\na\n", options)))
  options.check = true
  self:assert_equal("up to date", (generated_page.apply(path, "x.md", "<!-- generated -->\na\n", options)))
  state, problems = generated_page.apply(path, "x.md", "<!-- generated -->\nb\n", options)
  self:assert_equal("stale", state)
  self:assert_true(problems[1]:find("run lua tools/run.lua gen-x", 1, true) ~= nil)
  os.remove(path)
end

function T:test_a_page_without_the_marker_is_left_alone()
  local path = scratch()
  write(path, "written by hand\n")
  local state, problems = generated_page.apply(path, "x.md", "<!-- generated -->\n", { check = false, task = "gen-x",
    is_generated = is_generated })
  self:assert_equal("kept", state)
  self:assert_equal(1, #problems)
  self:assert_equal("written by hand\n", generated_page.read(path))
  os.remove(path)
end

return T
