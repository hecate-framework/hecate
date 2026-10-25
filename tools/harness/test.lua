-- Bootstrap test harness (ADR 0008): the xUnit vocabulary of the future `hecate.test`
-- (Case with test_* methods, set_up/tear_down, assert_*). Removed after Phase 3.
-- A test file returns a case; `run_case` executes it and returns results.
local M = {}

local Case = {}
Case.__index = Case

local function fail(message, level) error({ harness_failure = message }, level or 2) end

local function show(v) return type(v) == "string" and ("%q"):format(v) or tostring(v) end

function Case:fail(message) fail(message or "failed", 3) end
function Case:assert_true(v, msg) if not v then fail(msg or ("expected truthy, got " .. show(v)), 3) end end
function Case:assert_false(v, msg) if v then fail(msg or ("expected falsy, got " .. show(v)), 3) end end
function Case:assert_nil(v, msg) if v ~= nil then fail(msg or ("expected nil, got " .. show(v)), 3) end end
function Case:assert_not_nil(v, msg) if v == nil then fail(msg or "expected a value, got nil", 3) end end
function Case:assert_equal(expected, actual, msg)
  if expected ~= actual then
    fail(msg or ("expected %s, got %s"):format(show(expected), show(actual)), 3)
  end
end
--- Asserts that fn raises; returns the raised value. Optional pattern is matched
--- against the message when the raised value is a string.
function Case:assert_error(fn, pattern)
  local ok, err = pcall(fn)
  if ok then fail("expected an error, none raised", 3) end
  if pattern and type(err) == "string" and not err:find(pattern) then
    fail(("error %s does not match %s"):format(show(err), show(pattern)), 3)
  end
  return err
end

--- Creates a test case class.
---@param name string
---@return table
function M.Case(name)
  local class = setmetatable({ name = name }, { __index = Case })
  class.__index = class
  return class
end

--- Called with the full name of a test just before it runs (the file runner arms its watchdog here).
---@type fun(name: string)?
M.on_start = nil

--- Called with the full name of a test after it ran and was torn down, and whether it passed; returns a failure
--- message to fail the test (the file runner's leak detection, `leaks` task).
---@type (fun(name: string, passed: boolean): string?)?
M.on_finish = nil

--- Runs every test_* method of a case, in name order. Returns a list of results
--- { name, ok, message }.
---@param class table
---@return table[]
function M.run_case(class)
  local names = {}
  for k, v in pairs(class) do
    if type(k) == "string" and k:find("^test_") and type(v) == "function" then names[#names + 1] = k end
  end
  table.sort(names)
  local results = {}
  if class.set_up_case then class:set_up_case() end
  for _, n in ipairs(names) do
    if M.on_start then M.on_start((class.name or "case") .. "." .. n) end
    local self = setmetatable({}, class)
    local ok, err = pcall(function()
      if self.set_up then self:set_up() end
      local tok, terr = pcall(self[n], self)
      if self.tear_down then self:tear_down() end
      if not tok then error(terr, 0) end
    end)
    local message
    if not ok then message = type(err) == "table" and err.harness_failure or tostring(err) end
    if M.on_finish then
      local leak = M.on_finish((class.name or "case") .. "." .. n, ok)
      if ok and leak then ok, message = false, leak end
    end
    results[#results + 1] = { name = (class.name or "case") .. "." .. n, ok = ok, message = message }
  end
  if class.tear_down_case then class:tear_down_case() end
  return results
end

return M
