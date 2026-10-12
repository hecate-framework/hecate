local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local support = {
  run_virtual = function(fn, ...) return reactor.Reactor({ clock = "virtual" }):run(fn, ...) end,
}
local T = test.Case("ReactorTest")

function T:test_run_returns_the_results_of_the_main_function()
  local a, b = reactor.run(function(x, y) return x, y end, 1, 2)
  self:assert_equal(1, a)
  self:assert_equal(2, b)
end

function T:test_run_raises_the_error_of_the_main_function()
  local err = self:assert_error(function() reactor.run(function() error(core.ValidationError("main")) end) end)
  self:assert_true(core.is_instance_of(err, core.ValidationError))
end

function T:test_real_clock_sleep_takes_real_time()
  local elapsed = reactor.run(function()
    local start = reactor.now()
    reactor.sleep(0.05)
    return reactor.now() - start
  end)
  self:assert_true(elapsed >= 0.045, "elapsed " .. elapsed)
  self:assert_true(elapsed < 1, "elapsed " .. elapsed)
end

function T:test_real_clock_runs_sleepers_concurrently()
  local elapsed = reactor.run(function()
    local start = reactor.now()
    local futures = {}
    for i = 1, 50 do futures[i] = reactor.fork(reactor.sleep, 0.05) end
    reactor.join(table.unpack(futures))
    return reactor.now() - start
  end)
  self:assert_true(elapsed < 0.5, "elapsed " .. elapsed)
end

function T:test_real_clock_deadline()
  local ok, err = pcall(reactor.run, function() reactor.deadline(0.03, reactor.sleep, 5) end)
  self:assert_false(ok)
  self:assert_true(core.is_instance_of(err, core.DeadlineExceededError))
end

function T:test_no_libuv_handle_and_no_coroutine_leaks()
  local before = reactor.Reactor.open_handles()
  local instance = reactor.Reactor()
  instance:run(function()
    reactor.scope(function()
      for _ = 1, 20 do reactor.fork(reactor.sleep, 0.001) end
      pcall(reactor.deadline, 0.005, reactor.sleep, 1)
    end)
  end)
  self:assert_equal(0, instance:live_tasks())
  self:assert_equal(before, reactor.Reactor.open_handles())
end

function T:test_deadlock_is_reported_and_close_handlers_run()
  local closed = false
  local instance = reactor.Reactor({ clock = "virtual" })
  local err = self:assert_error(function()
    instance:run(function()
      local guard <close> = setmetatable({}, { __close = function() closed = true end }) -- hecate: test-only
      local waiting
      waiting = reactor.fork(function() return waiting:value() end)
      return waiting:value()
    end)
  end)
  self:assert_true(core.is_instance_of(err, core.Error))
  self:assert_true(err.message:find("deadlock") ~= nil)
  self:assert_true(closed)
  self:assert_equal(0, instance:live_tasks())
end

function T:test_nested_run_is_rejected()
  reactor.run(function()
    local err = self:assert_error(function() reactor.run(function() end) end)
    self:assert_true(core.is_instance_of(err, core.Error))
  end)
end

function T:test_a_reactor_is_usable_again_after_a_failed_run()
  pcall(reactor.run, function() error("first", 0) end)
  self:assert_equal("ok", reactor.run(function() return "ok" end))
end

function T:test_invalid_clock_is_rejected()
  local err = self:assert_error(function() reactor.Reactor({ clock = "wall" }) end)
  self:assert_true(core.is_instance_of(err, core.ArgumentError))
end

function T:test_stress_ten_thousand_concurrent_coroutines_virtual()
  local total = support.run_virtual(function()
    local futures = {}
    for i = 1, 10000 do
      futures[i] = reactor.fork(function() reactor.sleep(i % 10); return 1 end)
    end
    local sum = 0
    for i = 1, #futures do sum = sum + futures[i]:value() end
    return sum
  end)
  self:assert_equal(10000, total)
end

function T:test_stress_ten_thousand_concurrent_coroutines_real_clock()
  local total = reactor.run(function()
    local count = 0
    reactor.scope(function()
      for _ = 1, 10000 do
        reactor.fork(function() reactor.sleep(0.01); count = count + 1 end)
      end
    end)
    return count
  end)
  self:assert_equal(10000, total)
end

return T
