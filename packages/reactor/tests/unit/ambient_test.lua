local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local support = {
  run_virtual = function(fn, ...) return reactor.Reactor({ clock = "virtual" }):run(fn, ...) end,
}
local T = test.Case("AmbientTest")

local KEY = {}
local OTHER = {}

function T:test_a_binding_is_read_through_ambient()
  support.run_virtual(function()
    reactor.with_ambient(KEY, "v", function() self:assert_equal("v", reactor.ambient(KEY)) end)
  end)
end

function T:test_unbound_key_is_nil()
  support.run_virtual(function() self:assert_nil(reactor.ambient(KEY)) end)
end

function T:test_binding_is_visible_in_fn_and_returns_its_results()
  local a, b = support.run_virtual(function()
    return reactor.with_ambient(KEY, "v", function(x, y) return reactor.ambient(KEY), x + y end, 1, 2)
  end)
  self:assert_equal("v", a)
  self:assert_equal(3, b)
end

function T:test_binding_is_removed_on_return()
  support.run_virtual(function()
    reactor.with_ambient(KEY, "v", function() end)
    self:assert_nil(reactor.ambient(KEY))
  end)
end

function T:test_binding_is_removed_on_error()
  support.run_virtual(function()
    local ok = pcall(reactor.with_ambient, KEY, "v", function() error("boom") end)
    self:assert_false(ok)
    self:assert_nil(reactor.ambient(KEY))
  end)
end

function T:test_nested_binding_shadows_then_restores()
  support.run_virtual(function()
    reactor.with_ambient(KEY, 1, function()
      reactor.with_ambient(KEY, 2, function() self:assert_equal(2, reactor.ambient(KEY)) end)
      self:assert_equal(1, reactor.ambient(KEY))
    end)
  end)
end

function T:test_keys_are_independent()
  support.run_virtual(function()
    reactor.with_ambient(KEY, 1, function()
      reactor.with_ambient(OTHER, 2, function()
        self:assert_equal(1, reactor.ambient(KEY))
        self:assert_equal(2, reactor.ambient(OTHER))
      end)
    end)
  end)
end

function T:test_nil_key_is_an_argument_error()
  support.run_virtual(function()
    local err = self:assert_error(function() reactor.with_ambient(nil, 1, function() end) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError))
    local err2 = self:assert_error(function() reactor.ambient(nil) end)
    self:assert_true(core.is_instance_of(err2, core.ArgumentError))
    local err3 = self:assert_error(function()
      ---@diagnostic disable-next-line: param-type-mismatch  -- the point of the test
      reactor.with_ambient(KEY, 1, 42)
    end)
    self:assert_true(core.is_instance_of(err3, core.ArgumentError))
  end)
end

function T:test_outside_a_managed_coroutine_raises()
  local err = self:assert_error(function() reactor.ambient(KEY) end)
  self:assert_true(core.is_instance_of(err, core.NonYieldableContextError))
  local err2 = self:assert_error(function() reactor.with_ambient(KEY, 1, function() end) end)
  self:assert_true(core.is_instance_of(err2, core.NonYieldableContextError))
end

function T:test_fork_inherits_the_binding_at_the_moment_of_the_call()
  local seen = {}
  support.run_virtual(function()
    reactor.with_ambient(KEY, "request", function()
      local child = reactor.fork(function()
        reactor.sleep(1)
        seen.child = reactor.ambient(KEY)
        return reactor.ambient(KEY)
      end)
      reactor.with_ambient(OTHER, "later", function() end)
      self:assert_equal("request", child:value())
    end)
  end)
  self:assert_equal("request", seen.child)
end

function T:test_a_later_binding_of_the_creator_is_not_seen_by_the_child()
  support.run_virtual(function()
    local child
    reactor.with_ambient(KEY, 1, function()
      child = reactor.fork(function()
        reactor.sleep(1)
        return reactor.ambient(OTHER)
      end)
      reactor.with_ambient(OTHER, "late", function() reactor.sleep(5) end)
    end)
    self:assert_nil(child:value())
  end)
end

function T:test_child_binding_does_not_leak_to_siblings_or_parent()
  support.run_virtual(function()
    reactor.scope(function()
      local a = reactor.fork(function()
        return reactor.with_ambient(KEY, "a", function() reactor.sleep(2); return reactor.ambient(KEY) end)
      end)
      local b = reactor.fork(function() reactor.sleep(1); return reactor.ambient(KEY) end)
      self:assert_equal("a", a:value())
      self:assert_nil(b:value())
      self:assert_nil(reactor.ambient(KEY))
    end)
  end)
end

function T:test_detach_inherits_from_the_creator_not_the_application_scope()
  support.run_virtual(function()
    reactor.with_ambient(KEY, "creator", function()
      local future = reactor.detach(function() return reactor.ambient(KEY) end)
      self:assert_equal("creator", future:value())
    end)
  end)
end

function T:test_scope_fork_inherits()
  support.run_virtual(function()
    reactor.with_ambient(KEY, "x", function()
      reactor.scope(function(scope)
        self:assert_equal("x", reactor.ambient(KEY))
        self:assert_equal("x", scope:fork(function() return reactor.ambient(KEY) end):value())
      end)
    end)
  end)
end

function T:test_binding_is_removed_when_the_body_is_cancelled()
  local after
  support.run_virtual(function()
    local ok = pcall(reactor.scope, function()
      reactor.fork(function() reactor.sleep(1); error(core.ValidationError("child failed")) end)
      pcall(reactor.with_ambient, KEY, "v", function() reactor.sleep(50) end)
      after = reactor.ambient(KEY)
    end)
    self:assert_false(ok)
  end)
  self:assert_nil(after)
end

function T:test_binding_survives_suspension_with_the_virtual_clock()
  support.run_virtual(function()
    reactor.with_ambient(KEY, "v", function()
      reactor.sleep(10)
      self:assert_equal("v", reactor.ambient(KEY))
    end)
  end)
end

return T
