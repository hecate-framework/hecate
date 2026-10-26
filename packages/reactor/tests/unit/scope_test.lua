local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local support = {
  run_virtual = function(fn, ...) return reactor.Reactor({ clock = "virtual" }):run(fn, ...) end,
}
local T = test.Case("ScopeTest")

function T:test_scope_does_not_complete_before_its_children()
  local log = {}
  support.run_virtual(function()
    reactor.scope(function()
      reactor.fork(function() reactor.sleep(5); log[#log + 1] = "slow" end)
      reactor.fork(function() reactor.sleep(1); log[#log + 1] = "fast" end)
      log[#log + 1] = "body"
    end)
    log[#log + 1] = "after"
  end)
  self:assert_equal("body,fast,slow,after", table.concat(log, ","))
end

function T:test_scope_returns_the_values_of_its_body()
  local a, b = support.run_virtual(function()
    return reactor.scope(function() return "x", "y" end)
  end)
  self:assert_equal("x", a)
  self:assert_equal("y", b)
end

function T:test_run_waits_for_children_of_the_root_scope()
  local finished = false
  support.run_virtual(function()
    reactor.fork(function() reactor.sleep(3); finished = true end)
  end)
  self:assert_true(finished)
end

function T:test_a_failing_child_cancels_siblings_and_the_scope_raises_its_error()
  local sibling_closed = false
  local err = self:assert_error(function()
    support.run_virtual(function()
      reactor.scope(function()
        reactor.fork(function()
          local guard <close> = setmetatable({}, { __close = function() sibling_closed = true end }) -- hecate: test-only
          reactor.sleep(100)
        end)
        reactor.fork(function() reactor.sleep(1); error(core.ValidationError("child failed")) end)
        reactor.sleep(50) -- the body is cancelled too
        error("not reached")
      end)
    end)
  end)
  self:assert_true(core.is_instance_of(err, core.ValidationError))
  self:assert_equal("child failed", err.message)
  self:assert_true(sibling_closed)
end

function T:test_the_first_failure_wins()
  local err = self:assert_error(function()
    support.run_virtual(function()
      reactor.scope(function()
        reactor.fork(function() reactor.sleep(2); error("second", 0) end)
        reactor.fork(function() reactor.sleep(1); error("first", 0) end)
      end)
    end)
  end)
  self:assert_equal("first", err)
end

function T:test_a_failing_body_cancels_children_and_waits_for_them()
  local log = {}
  local err = self:assert_error(function()
    support.run_virtual(function()
      reactor.scope(function()
        reactor.fork(function()
          local ok = pcall(reactor.sleep, 100)
          log[#log + 1] = ok and "completed" or "cancelled"
        end)
        reactor.sleep(1)
        error("body failed", 0)
      end)
    end)
  end)
  self:assert_equal("body failed", err)
  self:assert_equal("cancelled", log[1])
end

function T:test_nested_scopes_wait_for_inner_children_first()
  local log = {}
  support.run_virtual(function()
    reactor.scope(function()
      reactor.fork(function() reactor.sleep(2); log[#log + 1] = "outer child" end)
      reactor.scope(function()
        reactor.fork(function() reactor.sleep(1); log[#log + 1] = "inner child" end)
      end)
      log[#log + 1] = "inner done"
    end)
    log[#log + 1] = "outer done"
  end)
  self:assert_equal("inner child,inner done,outer child,outer done", table.concat(log, ","))
end

function T:test_cancelling_an_outer_scope_cancels_nested_scopes()
  local log = {}
  support.run_virtual(function()
    reactor.scope(function(outer)
      reactor.fork(function() reactor.sleep(1); outer:cancel() end)
      reactor.scope(function()
        reactor.fork(function()
          local ok = pcall(reactor.sleep, 100)
          log[#log + 1] = ok and "completed" or "inner child cancelled"
        end)
        local ok = pcall(reactor.sleep, 100)
        log[#log + 1] = ok and "completed" or "inner body cancelled"
      end)
      pcall(reactor.sleep, 1)
    end)
  end)
  self:assert_equal(2, #log)
  self:assert_true(log[1]:find("cancelled") ~= nil and log[2]:find("cancelled") ~= nil)
end

function T:test_a_scope_absorbs_its_own_cancellation()
  local after = false
  support.run_virtual(function()
    reactor.scope(function(s)
      reactor.fork(function() reactor.sleep(1); s:cancel() end)
      reactor.sleep(100)
      error("not reached")
    end)
    after = true
  end)
  self:assert_true(after)
end

function T:test_cancellation_runs_the_pending_closes()
  local closed = {}
  support.run_virtual(function()
    local f = reactor.fork(function()
      local a <close> = setmetatable({}, { __close = function() closed[#closed + 1] = "a" end }) -- hecate: test-only
      local b <close> = setmetatable({}, { __close = function() closed[#closed + 1] = "b" end }) -- hecate: test-only
      reactor.sleep(100)
    end)
    reactor.sleep(1)
    f:cancel()
    pcall(f.value, f)
  end)
  self:assert_equal("b,a", table.concat(closed, ","))
end

function T:test_cancellation_is_level_triggered()
  support.run_virtual(function()
    local second_raised
    local f = reactor.fork(function()
      pcall(reactor.sleep, 100)
      second_raised = not pcall(reactor.sleep, 1)
      return second_raised
    end)
    reactor.sleep(1)
    f:cancel()
    self:assert_true(f:value())
  end)
end

function T:test_scope_fork_after_completion_is_rejected()
  support.run_virtual(function()
    local saved
    reactor.scope(function(s) saved = s end)
    local err = self:assert_error(function() saved:fork(function() end) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError))
  end)
end

function T:test_scope_fork_method_adds_children()
  local ran = false
  support.run_virtual(function()
    reactor.scope(function(s) s:fork(function() reactor.sleep(1); ran = true end) end)
  end)
  self:assert_true(ran)
end

function T:test_a_close_metamethod_error_replaces_the_cancellation()
  local err = self:assert_error(function()
    support.run_virtual(function()
      reactor.scope(function()
        reactor.fork(function()
          local g <close> = setmetatable({}, { __close = function() error("cleanup failed", 0) end }) -- hecate: test-only
          reactor.sleep(100)
        end)
        reactor.sleep(1)
        error("body", 0)
      end)
    end)
  end)
  self:assert_equal("body", err)
end

return T
