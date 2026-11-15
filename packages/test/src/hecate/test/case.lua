-- Test case: an xUnit class whose `test_*` methods are tests (Meszaros 2007, "Testcase Class").
global <const> type, pairs, require, table

local core = require("hecate.core")
local assertions = require("hecate.test.assertions")

--- The base class of every test case: the assertions, and the lifecycle hooks (empty by default).
---@class hecate.test.Case : hecate.test.Assertions
---@field [string] any  tests, fixtures and attributes that a case declares on itself
---@field clock? "real"|"virtual"  clock of the reactors of this case, over the option of the runner
---@field tags? string[]  tags of every test of the case, selected by the `tags` and `exclude_tags` options of the runner
---@field test_tags? table<string, string[]>  tags of single tests, by method name
---@field test_parameters? table<string, any[]>  parametrised tests by method name: the test runs once per entry, which it receives as its argument; an entry that is a table may set `label` (else its index) to name the test `Case.test_x[label]`
---@field set_up? fun(self: hecate.test.Case)  runs before each test, on the instance of that test
---@field tear_down? fun(self: hecate.test.Case)  runs after each test whose `set_up` succeeded, whatever its outcome
---@field set_up_case? fun(self: hecate.test.Case)  runs once before the first test of the case, on a case-level instance whose fields are copied onto the instance of every test
---@field tear_down_case? fun(self: hecate.test.Case)  runs once after the last test, on the case-level instance
local Base = core.class("Case")
for name, method in pairs(assertions.Assertions) do Base[name] = method end
core.finalise(Base)

---@class hecate.test.case
---@field Base hecate.test.Case
local M = { Base = Base }

--- Declares a test case. Add `test_*` methods (and optionally `set_up`, `tear_down`,
--- `set_up_case`, `tear_down_case`) to the returned class and return it from a `*_test.lua`
--- file; the runner finalises it. A case may extend another case with `core.class`.
---@param name string  the name of the case, the prefix of the names of its tests
---@return hecate.test.Case class  a class, not yet finalised
function M.Case(name)
  local class = core.class(name, Base) --[[@as hecate.test.Case]]
  class.name = name -- the bootstrap harness names the tests of a case after this field
  return class
end

--- Returns the names of the tests of a case: its `test_*` functions, in name order.
---@param class table  a case
---@return string[] names
function M.test_names(class)
  local names = {}
  for key, value in pairs(class) do
    if type(key) == "string" and key:find("^test_") and type(value) == "function" then names[#names + 1] = key end
  end
  table.sort(names)
  return names
end

--- Returns whether `value` is a test case (a class derived from `Case`).
---@param value any
---@return boolean
function M.is_case(value)
  if type(value) ~= "table" or not core.is_class(value) then return false end
  local current = core.superclass(value)
  while current do
    if current == Base then return true end
    current = core.superclass(current)
  end
  return false
end

return M
