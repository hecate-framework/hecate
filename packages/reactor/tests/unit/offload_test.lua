---@diagnostic disable: param-type-mismatch, assign-type-mismatch  -- the tests pass invalid arguments on purpose
-- `reactor.offload` (concurrency.md, "Offload"; OQ-119): self-contained functions on the libuv
-- thread pool, values copied between Lua states, errors, cancellation and the reactor clock.
local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local context = require("hecate.reactor.internal.context")
local T = test.Case("OffloadTest")

--- Runs `fn` on a real-clock reactor and returns its results.
local function run(fn, ...) return reactor.run(fn, ...) end

local function assert_argument_error(self, fn, pattern)
  local err = self:assert_error(function() run(fn) end)
  self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
  if pattern then self:assert_true(tostring(err):find(pattern, 1, true) ~= nil, tostring(err)) end
  return err
end

local function assert_offload_error(self, fn, pattern)
  local err = self:assert_error(function() run(fn) end)
  self:assert_true(core.is_instance_of(err, reactor.OffloadError), tostring(err))
  self:assert_true(core.is_instance_of(err, core.Error), tostring(err))
  if pattern then self:assert_true(tostring(err):find(pattern, 1, true) ~= nil, tostring(err)) end
  return err
end

-- Values ----------------------------------------------------------------------------------------

function T:test_the_results_of_the_function_are_returned()
  local sum, text = run(function()
    return reactor.offload(function(a, b) return a + b, ("%d+%d"):format(a, b) end, 2, 3)
  end)
  self:assert_equal(5, sum)
  self:assert_equal("2+3", text)
end

function T:test_scalars_keep_their_type_and_subtype()
  local results = table.pack(run(function()
    return reactor.offload(function(...) return ... end, 1, 1.0, -0.0, math.maxinteger, math.mininteger,
      math.huge, -math.huge, true, false, "", "a\0b\255")
  end))
  self:assert_equal(11, results.n)
  self:assert_equal("integer", math.type(results[1]))
  self:assert_equal("float", math.type(results[2]))
  self:assert_equal(-math.huge, 1 / results[3]) -- the sign of zero is kept
  self:assert_equal(math.maxinteger, results[4])
  self:assert_equal(math.mininteger, results[5])
  self:assert_equal(math.huge, results[6])
  self:assert_equal(-math.huge, results[7])
  self:assert_equal(true, results[8])
  self:assert_equal(false, results[9])
  self:assert_equal("", results[10])
  self:assert_equal("a\0b\255", results[11])
end

function T:test_not_a_number_crosses()
  local value = run(function() return reactor.offload(function(x) return x end, 0 / 0) end)
  self:assert_true(value ~= value)
end

function T:test_nil_arguments_and_results_keep_their_place()
  local results = table.pack(run(function()
    return reactor.offload(function(...) return select("#", ...), ... end, nil, 2, nil)
  end))
  self:assert_equal(4, results.n)
  self:assert_equal(3, results[1])
  self:assert_nil(results[2])
  self:assert_equal(2, results[3])
  self:assert_nil(results[4])
  local none = table.pack(run(function() return reactor.offload(function() end) end))
  self:assert_equal(0, none.n)
end

function T:test_more_than_nine_arguments_and_results_cross()
  local results = table.pack(run(function()
    return reactor.offload(function(...) return ... end, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12)
  end))
  self:assert_equal(12, results.n)
  for i = 1, 12 do self:assert_equal(i, results[i]) end
end

function T:test_plain_tables_cross_in_both_directions()
  local copy = run(function()
    return reactor.offload(function(t)
      t.list[#t.list + 1] = "c"
      return t
    end, { list = { "a", "b" }, nested = { deep = { value = 1.5 } }, [true] = "yes", [2.5] = "half", [7] = 7 })
  end)
  self:assert_equal(3, #copy.list)
  self:assert_equal("c", copy.list[3])
  self:assert_equal(1.5, copy.nested.deep.value)
  self:assert_equal("yes", copy[true])
  self:assert_equal("half", copy[2.5])
  self:assert_equal(7, copy[7])
end

function T:test_a_table_reached_twice_is_copied_twice()
  local shared = { 1 }
  local a, b = run(function()
    return reactor.offload(function(t) return t.first, t.second end, { first = shared, second = shared })
  end)
  self:assert_equal(1, a[1])
  self:assert_equal(1, b[1])
  self:assert_true(a ~= b)
end

function T:test_large_strings_cross()
  local data = ("0123456789"):rep(500000)
  local length, last = run(function()
    return reactor.offload(function(s) return #s, s:sub(-1) end, data)
  end)
  self:assert_equal(#data, length)
  self:assert_equal("9", last)
end

function T:test_tables_up_to_one_hundred_levels_cross()
  local function nest(levels)
    local root = {}
    local node = root
    for _ = 2, levels do
      node.next = {}
      node = node.next
    end
    return root
  end
  local depth = run(function()
    return reactor.offload(function(t)
      local count = 0
      while t do count, t = count + 1, t.next end
      return count
    end, nest(100))
  end)
  self:assert_equal(100, depth)
  assert_argument_error(self, function() reactor.offload(function() end, nest(101)) end, "argument 1")
end

-- The pool thread -------------------------------------------------------------------------------

function T:test_the_function_runs_in_a_separate_state()
  local loaded, has_string = run(function()
    return reactor.offload(function()
      return package.loaded["hecate.reactor"] ~= nil, type(string.format) == "function"
    end)
  end)
  self:assert_false(loaded)
  self:assert_true(has_string)
end

function T:test_the_reactor_keeps_running_while_a_function_runs()
  local ticks = run(function()
    local count = 0
    local ticker = reactor.fork(function()
      while true do
        count = count + 1
        reactor.sleep(0.005)
      end
    end)
    reactor.offload(function()
      -- Busy on purpose. os.clock: process CPU time on Linux and macOS (all threads), wall time on Windows;
      -- either way the loop ends after at most about 0.3 s of wall time while it is scheduled.
      local stop = os.clock() + 0.3
      while os.clock() < stop do end
    end)
    ticker:cancel()
    return count
  end)
  self:assert_true(ticks >= 3, ("the reactor ticked %d times"):format(ticks))
end

function T:test_several_functions_run_at_once()
  local results = run(function()
    local futures = {}
    for i = 1, 16 do
      futures[i] = reactor.fork(function()
        return reactor.offload(function(n)
          local sum = 0
          for k = 1, 100000 do sum = sum + k % n end
          return n, sum
        end, i)
      end)
    end
    local out = {}
    for i = 1, 16 do out[i] = futures[i]:value() end
    return out
  end)
  for i = 1, 16 do self:assert_equal(i, results[i]) end
end

-- Errors ----------------------------------------------------------------------------------------

function T:test_an_error_of_the_function_is_raised_as_an_offload_error()
  local err = assert_offload_error(self, function()
    reactor.offload(function() error("boom") end)
  end, "boom")
  self:assert_true(err.message:find("^reactor%.offload: ") ~= nil, err.message)
  self:assert_true(type(err.context.traceback) == "string" and err.context.traceback:find("boom", 1, true) ~= nil)
end

function T:test_the_message_field_of_an_error_object_is_used()
  local err = assert_offload_error(self, function()
    reactor.offload(function() error({ message = "structured failure", code = "hecate.example.Failure" }) end)
  end, "structured failure")
  self:assert_equal("raised", err.context.reason)
  self:assert_equal("hecate.example.Failure", err.context.code)
end

function T:test_a_function_cannot_break_the_next_ones_through_globals()
  local leaked, debug_kind = run(function()
    local futures = {}
    for i = 1, 16 do -- more calls than pool threads, so every thread sees one
      futures[i] = reactor.fork(reactor.offload, function()
        _ENV.leaked_global = true -- assignments to globals, on purpose
        _ENV.debug = nil
        _ENV.pcall = nil
      end)
    end
    for i = 1, 16 do futures[i]:value() end
    for i = 1, 16 do
      futures[i] = reactor.fork(reactor.offload, function() return _ENV.leaked_global, type(debug) end)
    end
    local any_leak, kind = false, nil
    for i = 1, 16 do
      local value, k = futures[i]:value()
      any_leak = any_leak or value ~= nil
      kind = k
    end
    return any_leak, kind
  end)
  self:assert_false(leaked)
  self:assert_equal("table", debug_kind)
end

function T:test_a_stripped_function_is_refused_with_a_clear_message()
  local stripped = load(string.dump(function() return math.pi end, true))
  assert_argument_error(self, function() reactor.offload(stripped) end, "stripped")
end

function T:test_an_error_that_cannot_be_converted_to_a_string_is_reported()
  assert_offload_error(self, function()
    reactor.offload(function()
      error(setmetatable({}, { __tostring = function() error("no") end }))
    end, nil)
  end, "cannot be converted")
end

function T:test_a_result_that_cannot_cross_raises_an_offload_error()
  local err = assert_offload_error(self, function() reactor.offload(function() return 1, print end) end, "result 2")
  self:assert_equal("result", err.context.reason)
  self:assert_nil(err.context.traceback)
  assert_offload_error(self, function()
    reactor.offload(function() return { inner = coroutine.create(print) } end)
  end, "result 1.inner")
  assert_offload_error(self, function()
    reactor.offload(function() local t = {}; t.self = t; return t end)
  end, "contains itself")
end

function T:test_the_reactor_is_healthy_after_a_failure()
  local value = run(function()
    pcall(reactor.offload, function() error("first") end)
    return reactor.offload(function() return "second" end)
  end)
  self:assert_equal("second", value)
end

-- Arguments -------------------------------------------------------------------------------------

function T:test_the_function_is_validated()
  assert_argument_error(self, function() reactor.offload(42) end, "expects a function")
  assert_argument_error(self, function() reactor.offload(print) end, "C function")
  local captured = 1
  assert_argument_error(self, function() reactor.offload(function() return captured end) end, "captured")
end

function T:test_arguments_that_cannot_cross_are_refused()
  assert_argument_error(self, function() reactor.offload(function() end, print) end, "argument 1")
  assert_argument_error(self, function() reactor.offload(function() end, 1, setmetatable({}, {})) end,
    "argument 2: a table with a metatable")
  assert_argument_error(self, function() reactor.offload(function() end, { [print] = 1 }) end, "key of type function")
  local cycle = {}
  cycle.again = { cycle }
  assert_argument_error(self, function() reactor.offload(function() end, cycle) end, "contains itself")
end

-- Scheduling ------------------------------------------------------------------------------------

function T:test_a_cancelled_caller_is_released_and_the_result_discarded()
  local before = reactor.Reactor.open_handles()
  local value = run(function()
    local worker = reactor.fork(function()
      return reactor.offload(function()
        local stop = os.clock() + 0.02 -- see the comment on os.clock above
        while os.clock() < stop do end
        return "late"
      end)
    end)
    reactor.sleep(0)
    worker:cancel()
    self:assert_error(function() worker:value() end)
    self:assert_equal("cancelled", worker:state())
    -- Lets the late result arrive and be discarded inside this run, even on a slow runner.
    for _ = 1, 200 do
      if (context.offloads_in_flight or 0) == 0 then break end
      reactor.sleep(0.01)
    end
    self:assert_equal(0, context.offloads_in_flight or 0)
    return reactor.offload(function() return "healthy" end)
  end)
  self:assert_equal("healthy", value)
  self:assert_equal(before, reactor.Reactor.open_handles())
end

function T:test_a_deadline_releases_the_caller()
  local err = self:assert_error(function()
    run(function()
      reactor.deadline(0.01, reactor.offload, function()
        local stop = os.clock() + 0.05 -- longer than the deadline; see the comment on os.clock above
        while os.clock() < stop do end
      end)
    end)
  end)
  self:assert_true(core.is_instance_of(err, core.DeadlineExceededError), tostring(err))
end

function T:test_offload_needs_the_real_clock()
  local err = self:assert_error(function()
    reactor.Reactor({ clock = "virtual" }):run(function() reactor.offload(function() end) end)
  end)
  self:assert_true(core.is_instance_of(err, core.Error), tostring(err))
  self:assert_true(tostring(err):find("real clock", 1, true) ~= nil, tostring(err))
end

function T:test_offload_requires_a_managed_coroutine()
  local err = self:assert_error(function() reactor.offload(function() end) end)
  self:assert_true(core.is_instance_of(err, core.NonYieldableContextError), tostring(err))
end

return T
