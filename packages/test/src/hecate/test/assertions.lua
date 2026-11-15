-- The assertions of a test case. Each raises `hecate.test.AssertionFailure` (failure.lua) and
-- is installed as a method on the base class of every case (case.lua). Names and argument
-- order are those of the bootstrap harness (ADR 0008): `assert_equal(expected, actual, message)`.
global <const> type, pcall, math, table, pairs, ipairs, rawequal, require

local core = require("hecate.core")
local diff = require("hecate.test.diff")
local failure = require("hecate.test.failure")

local show = diff.show
local fail = failure.fail

--- Assertions available on every test case through `self`.
---@class hecate.test.Assertions
local Assertions = {}

--- Fails the test unconditionally.
---@param message? string  the reason (default "failed")
function Assertions:fail(message) fail(message or "failed") end

--- Asserts that `value` is truthy.
---@param value any
---@param message? string
function Assertions:assert_true(value, message)
  if not value then fail(message or ("expected truthy, got " .. show(value))) end
end

--- Asserts that `value` is `nil` or `false`.
---@param value any
---@param message? string
function Assertions:assert_false(value, message)
  if value then fail(message or ("expected falsy, got " .. show(value))) end
end

--- Asserts that `value` is `nil`.
---@param value any
---@param message? string
function Assertions:assert_nil(value, message)
  if value ~= nil then fail(message or ("expected nil, got " .. show(value))) end
end

--- Asserts that `value` is not `nil`.
---@param value any
---@param message? string
function Assertions:assert_not_nil(value, message)
  if value == nil then fail(message or "expected a value, got nil") end
end

--- Asserts that `actual` equals `expected`: by `==` for non-tables, structurally for tables
--- (same keys, structurally equal values; metatables ignored). The failure lists the
--- differences by path.
---@param expected any
---@param actual any
---@param message? string  replaces the generated description
function Assertions:assert_equal(expected, actual, message)
  if expected == actual then return end
  local equal, differences = diff.compare(expected, actual)
  if equal then return end
  local summary = ("expected %s, got %s"):format(show(expected), show(actual))
  if type(expected) == "table" and type(actual) == "table" then
    summary = "tables differ:\n  " .. table.concat(differences, "\n  ")
  end
  fail(message and (message .. "\n" .. summary) or summary,
    { expected = expected, actual = actual, differences = differences })
end

--- Asserts that `actual` is not structurally equal to `unexpected`.
---@param unexpected any
---@param actual any
---@param message? string
function Assertions:assert_not_equal(unexpected, actual, message)
  if (diff.compare(unexpected, actual)) then
    fail(message or ("expected a value different from " .. show(actual)))
  end
end

--- Asserts that `actual` is the very same value as `expected` (`rawequal`: identity for tables).
---@param expected any
---@param actual any
---@param message? string
function Assertions:assert_same(expected, actual, message)
  if not rawequal(expected, actual) then
    fail(message or ("expected the same value as %s, got %s"):format(show(expected), show(actual)))
  end
end

--- Asserts that two numbers differ by at most `tolerance` (absolute).
---@param expected number
---@param actual number
---@param tolerance? number  default 1e-9
---@param message? string
function Assertions:assert_near(expected, actual, tolerance, message)
  tolerance = tolerance or 1e-9
  if type(expected) ~= "number" or type(actual) ~= "number" then
    fail(message or ("expected numbers, got %s and %s"):format(show(expected), show(actual)))
  end
  if not (math.abs(expected - actual) <= tolerance) then
    fail(message or ("expected %s within %s of %s, got %s"):format(
      show(actual), show(tolerance), show(expected), show(math.abs(expected - actual))),
      { expected = expected, actual = actual })
  end
end

--- Asserts that the string `subject` matches the Lua pattern `pattern`.
---@param pattern string  a Lua pattern
---@param subject string
---@param message? string
function Assertions:assert_match(pattern, subject, message)
  if type(subject) ~= "string" then
    fail(message or ("expected a string to match %s, got %s"):format(show(pattern), show(subject)))
  end
  if not subject:find(pattern) then
    fail(message or ("%s does not match %s"):format(show(subject), show(pattern)))
  end
end

--- Expectation of `assert_error` beyond "something was raised".
---@class hecate.test.ErrorExpectation
---@field class? table  the raised value must be an instance of this class
---@field code? string  the raised error must have this `code`
---@field pattern? string  Lua pattern the message must match (`message` of an error object, the string itself otherwise)
---@field message? string  exact message

local function message_of(err)
  if type(err) == "string" then return err end
  if type(err) == "table" and type(err.message) == "string" then return err.message end
  return nil
end

--- Asserts that `fn` raises, and returns the raised value. `expectation` is a Lua pattern
--- matched against the message (as in the bootstrap harness) or an `ErrorExpectation`
--- (error class, stable code, pattern, exact message).
---@param fn function
---@param expectation? string|hecate.test.ErrorExpectation
---@return any raised  the raised value
function Assertions:assert_error(fn, expectation)
  local ok, err = pcall(fn)
  if ok then fail("expected an error, none raised") end
  if type(expectation) == "string" then expectation = { pattern = expectation } end
  if expectation then
    local text = message_of(err)
    if expectation.class and not core.is_instance_of(err, expectation.class) then
      fail(("expected an error of class %s, got %s"):format(core.name(expectation.class), show(text or err)),
        { actual = err })
    end
    if expectation.code and (type(err) ~= "table" or err.code ~= expectation.code) then
      fail(("expected an error with code %s, got %s"):format(show(expectation.code),
        show(type(err) == "table" and err.code or err)), { actual = err })
    end
    if expectation.pattern and not (text and text:find(expectation.pattern)) then
      fail(("error %s does not match %s"):format(show(text or err), show(expectation.pattern)), { actual = err })
    end
    if expectation.message and text ~= expectation.message then
      fail(("expected error message %s, got %s"):format(show(expectation.message), show(text or err)),
        { actual = err })
    end
  end
  return err
end

--- Returns a shape predicate: true for a value whose Lua type is `name`.
---@param name string  a result of `type`
---@return fun(value: any): boolean
local function of_type(name)
  return function(value) return type(value) == name end
end

--- Asserts that `value` has the given shape. A shape is a table: each entry is a function (a
--- predicate, true when the value is acceptable; see `hecate.test.of_type`), a table (the
--- value must be a table of that shape) or another value (compared with `==`). Keys of `value`
--- absent from the shape are ignored.
---@param shape table
---@param value any
---@param message? string
function Assertions:assert_shape(shape, value, message)
  local problems = {}
  local function check(s, v, path)
    if type(v) ~= "table" then
      problems[#problems + 1] = ("%s: expected a table, got %s"):format(path, show(v))
      return
    end
    local keys = {}
    for k in pairs(s) do keys[#keys + 1] = k end
    table.sort(keys, diff.key_before)
    for _, k in ipairs(keys) do
      local want, got = s[k], v[k]
      local child = path .. (type(k) == "string" and ("." .. k) or ("[" .. show(k, 0) .. "]"))
      if type(want) == "function" then
        if not want(got) then problems[#problems + 1] = ("%s: %s does not satisfy the predicate"):format(child, show(got)) end
      elseif type(want) == "table" then check(want, got, child)
      elseif want ~= got then
        problems[#problems + 1] = ("%s: expected %s, got %s"):format(child, show(want), show(got))
      end
    end
  end
  check(shape, value, "<root>")
  if #problems > 0 then
    local summary = "shape mismatch:\n  " .. table.concat(problems, "\n  ")
    fail(message and (message .. "\n" .. summary) or summary, { actual = value, differences = problems })
  end
end

return { Assertions = Assertions, of_type = of_type }
