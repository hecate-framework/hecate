-- Persistent signal watcher (`reactor.SignalWatcher`) and the capability queries of the process
-- primitives. Real signals are raised in this process with `uv.kill`; Windows delivers only the
-- console signals, so those tests are skipped there.
local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local uv = require("luv")
local T = test.Case("SignalTest")

local is_windows = package.config:sub(1, 1) == "\\"

--- Runs `fn` on a reactor; returns its results after checking that no libuv handle is left.
local function run(self, fn)
  local before = reactor.Reactor.open_handles()
  local results = table.pack(reactor.run(fn))
  self:assert_equal(before, reactor.Reactor.open_handles())
  return table.unpack(results, 1, results.n)
end

local function skip_on_windows(self)
  if is_windows then
    print("SKIP " .. self.name .. ": Windows delivers only the console signals, not signals raised by kill")
  end
  return is_windows
end

function T:test_delivery_while_waiting()
  if skip_on_windows(self) then return end
  local name = run(self, function()
    local watcher <close> = reactor.watch_signals("sigusr1")
    reactor.fork(function()
      reactor.sleep(0.01)
      uv.kill(uv.os_getpid(), "sigusr1")
    end)
    return watcher:wait()
  end)
  self:assert_equal("sigusr1", name)
end

function T:test_a_signal_arriving_while_nobody_waits_is_returned_by_the_next_wait()
  if skip_on_windows(self) then return end
  local name = run(self, function()
    local watcher <close> = reactor.watch_signals("sigusr1", "sigusr2")
    uv.kill(uv.os_getpid(), "sigusr2") -- no guard handle: the watcher alone keeps the default action off
    reactor.sleep(0.02) -- the signal is delivered while nothing waits
    self:assert_equal(1, watcher:pending())
    return watcher:wait()
  end)
  self:assert_equal("sigusr2", name)
end

function T:test_two_signals_are_queued_in_arrival_order_and_repeats_collapse()
  if skip_on_windows(self) then return end
  local first, second, third = run(self, function()
    local watcher <close> = reactor.watch_signals("sigusr1", "sigusr2")
    uv.kill(uv.os_getpid(), "sigusr2")
    reactor.sleep(0.02)
    uv.kill(uv.os_getpid(), "sigusr1")
    reactor.sleep(0.02)
    uv.kill(uv.os_getpid(), "sigusr1") -- identical to a queued one: collapsed
    reactor.sleep(0.02)
    self:assert_equal(2, watcher:pending())
    local a, b = watcher:wait(), watcher:wait()
    return a, b, watcher:pending()
  end)
  self:assert_equal("sigusr2", first)
  self:assert_equal("sigusr1", second)
  self:assert_equal(0, third)
end

function T:test_cancelling_a_waiter_keeps_the_watcher_and_its_queue()
  if skip_on_windows(self) then return end
  local name = run(self, function()
    local watcher <close> = reactor.watch_signals("sigusr1")
    local ok = pcall(reactor.deadline, 0.02, watcher.wait, watcher)
    self:assert_false(ok)
    self:assert_false(watcher:is_closed())
    uv.kill(uv.os_getpid(), "sigusr1") -- the watcher still owns its handle
    reactor.sleep(0.02)
    self:assert_equal(1, watcher:pending())
    return watcher:wait()
  end)
  self:assert_equal("sigusr1", name)
end

function T:test_close_releases_the_handles_and_is_idempotent()
  local before = reactor.Reactor.open_handles()
  reactor.run(function()
    local inside = reactor.Reactor.open_handles()
    local watcher = reactor.watch_signals("sigint", "sigterm")
    self:assert_equal(inside + 2, reactor.Reactor.open_handles())
    watcher:close()
    watcher:close()
    self:assert_true(watcher:is_closed())
    self:assert_equal(inside, reactor.Reactor.open_handles())
  end)
  self:assert_equal(before, reactor.Reactor.open_handles())
end

function T:test_an_idle_watcher_does_not_keep_the_loop_alive()
  run(self, function()
    local watcher <close> = reactor.watch_signals("sigint")
    -- Nothing waits: the run ends (a referenced handle would only matter after the main
    -- coroutine ended, so check the reference flag directly).
    for _, handle in ipairs({ watcher._handles[1] }) do self:assert_false(handle:has_ref()) end
  end)
end

function T:test_a_waiting_watcher_keeps_the_loop_alive_and_unrefs_afterwards()
  run(self, function()
    local watcher <close> = reactor.watch_signals("sigint")
    local handle = watcher._handles[1]
    reactor.fork(function()
      reactor.sleep(0.01)
      self:assert_true(handle:has_ref())
    end)
    pcall(reactor.deadline, 0.03, watcher.wait, watcher)
    self:assert_false(handle:has_ref())
  end)
end

function T:test_wait_after_close_raises()
  run(self, function()
    local watcher = reactor.watch_signals("sigint")
    watcher:close()
    local err = self:assert_error(function() watcher:wait() end)
    self:assert_true(core.is_instance_of(err, core.Error), tostring(err))
  end)
end

function T:test_closing_wakes_a_waiter_with_an_error()
  local ok = run(self, function()
    local watcher = reactor.watch_signals("sigint")
    reactor.fork(function() reactor.sleep(0.01); watcher:close() end)
    return (pcall(watcher.wait, watcher))
  end)
  self:assert_false(ok)
end

function T:test_a_refused_name_raises_io_error_and_leaks_nothing()
  run(self, function()
    local err = self:assert_error(function() reactor.watch_signals("sigint", "sigfoo") end)
    self:assert_true(core.is_instance_of(err, reactor.IoError), tostring(err))
    self:assert_equal("watch_signals", err.context.operation)
  end)
end

function T:test_arguments_are_validated()
  run(self, function()
    local none = self:assert_error(function() reactor.watch_signals() end)
    self:assert_true(core.is_instance_of(none, core.ArgumentError))
    local bad = self:assert_error(function() reactor.watch_signals("sigint", 2) end)
    self:assert_true(core.is_instance_of(bad, core.ArgumentError))
  end)
end

function T:test_wait_requires_a_managed_coroutine()
  local watcher
  reactor.run(function() watcher = reactor.watch_signals("sigint") end)
  local err = self:assert_error(function() watcher:wait() end)
  self:assert_true(core.is_instance_of(err, core.NonYieldableContextError))
  watcher:close()
end

function T:test_capability_queries_have_the_shape_of_supports_reuseport()
  for _, query in ipairs({ reactor.supports_spawn, reactor.supports_handle_passing }) do
    local supported, reason = query()
    self:assert_equal("boolean", type(supported))
    if supported then
      self:assert_equal(nil, reason)
    else
      self:assert_equal("string", type(reason))
    end
  end
end

function T:test_capability_queries_are_true_where_the_primitives_exist()
  -- Linux, macOS and Windows all provide spawn and ipc pipes in libuv (verified here on Linux only).
  self:assert_true((reactor.supports_spawn()))
  self:assert_true((reactor.supports_handle_passing()))
end

function T:test_capability_queries_report_a_missing_primitive()
  local spawn = uv.spawn
  uv.spawn = nil
  local supported, reason = reactor.supports_spawn()
  uv.spawn = spawn
  self:assert_false(supported)
  self:assert_equal("string", type(reason))
  local new_pipe = uv.new_pipe
  uv.new_pipe = function() return nil, "EMFILE: too many open files" end
  local passing, why = reactor.supports_handle_passing()
  uv.new_pipe = new_pipe
  self:assert_false(passing)
  self:assert_true(why ~= nil and why:find("EMFILE", 1, true) ~= nil, why)
end

return T
