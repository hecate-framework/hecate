local test = require("harness.test")
local reactor = require("hecate.reactor")
local serve = require("hecate.cli.serve")
local T = test.Case("CliServeTest")

--- A child that lives until `exit` is called (or until it reacts to a signal, as `on_kill` says).
local function fake_child(log, name, on_kill)
  local child = { name = name, killed = {} }
  function child:wait()
    while not self.status do reactor.sleep(0.001) end
    return self.status
  end
  function child:kill(signal)
    self.killed[#self.killed + 1] = signal
    log[#log + 1] = name .. " <- " .. tostring(signal)
    if on_kill then on_kill(self, signal) end
  end
  function child:exit(code, signal) self.status = { code = code or 0, signal = signal or 0 } end
  return child
end

--- A signal source fed by `send`.
local function fake_signals()
  local queue = {}
  return {
    send = function(name) queue[#queue + 1] = name end,
    wait = function()
      while #queue == 0 do reactor.sleep(0.001) end
      return table.remove(queue, 1)
    end,
  }
end

local function run(fn) return reactor.run(fn) end

function T:test_the_exit_code_of_the_child_is_the_one_of_this_process()
  self:assert_equal(0, serve.exit_code({ code = 0, signal = 0 }))
  self:assert_equal(3, serve.exit_code({ code = 3, signal = 0 }))
  self:assert_equal(137, serve.exit_code({ code = 0, signal = 9 }))
  self:assert_equal(143, serve.exit_code({ code = 1, signal = 15 }))
end

function T:test_without_watch_the_supervision_ends_with_the_child()
  local log, starts = {}, 0
  local code = run(function()
    return serve.supervise(reactor, {
      start = function() starts = starts + 1; local child = fake_child(log, "a"); child:exit(7); return child end,
      signals = fake_signals(),
    })
  end)
  self:assert_equal(7, code)
  self:assert_equal(1, starts)
end

function T:test_sigint_and_sigterm_are_forwarded_as_they_came()
  for _, name in ipairs({ "sigint", "sigterm" }) do
    local log = {}
    local signals = fake_signals()
    signals.send(name)
    local code = run(function()
      return serve.supervise(reactor, {
        start = function()
          return fake_child(log, "a", function(child) reactor.fork(function() reactor.sleep(0.01); child:exit(0) end) end)
        end,
        signals = signals,
      })
    end)
    self:assert_equal(0, code)
    self:assert_equal("a <- " .. name, table.concat(log, ","))
  end
end

function T:test_a_child_that_does_not_stop_is_killed_after_the_grace_period()
  local log = {}
  local signals = fake_signals()
  signals.send("sigterm")
  local code = run(function()
    return serve.supervise(reactor, {
      start = function()
        return fake_child(log, "a", function(child, signal)
          if signal == "sigkill" then child:exit(0, 9) end   -- sigterm is ignored
        end)
      end,
      signals = signals,
      grace = 0.05,
    })
  end)
  self:assert_equal(137, code)
  self:assert_equal("a <- sigterm,a <- sigkill", table.concat(log, ","))
end

function T:test_with_a_shared_console_the_signal_is_not_forwarded_and_the_child_is_killed_after_the_grace_period()
  -- Windows: the child got Ctrl+C from the console itself, and `kill` is TerminateProcess.
  local log = {}
  local signals = fake_signals()
  signals.send("sigint")
  signals.send("sighup")
  local code = run(function()
    return serve.supervise(reactor, {
      start = function()
        return fake_child(log, "a", function(child, signal) if signal == "sigkill" then child:exit(1) end end)
      end,
      signals = signals,
      shared_console = true,
      grace = 0.05,
    })
  end)
  self:assert_equal(1, code)
  self:assert_equal("a <- sigkill", table.concat(log, ","))
end

function T:test_with_a_shared_console_a_child_that_stops_by_itself_is_not_killed()
  local log = {}
  local signals = fake_signals()
  signals.send("sigterm")
  local code = run(function()
    return serve.supervise(reactor, {
      start = function()
        local child = fake_child(log, "a")
        reactor.fork(function() reactor.sleep(0.01); child:exit(0) end)
        return child
      end,
      signals = signals,
      shared_console = true,
      grace = 5,
    })
  end)
  self:assert_equal(0, code)
  self:assert_equal("", table.concat(log, ","))
end

function T:test_sighup_is_forwarded_and_the_child_keeps_running()
  local log = {}
  local signals = fake_signals()
  signals.send("sighup")
  signals.send("sigterm")
  local code = run(function()
    return serve.supervise(reactor, {
      start = function()
        return fake_child(log, "a", function(child, signal)
          if signal == "sigterm" then child:exit(0) end
        end)
      end,
      signals = signals,
    })
  end)
  self:assert_equal(0, code)
  self:assert_equal("a <- sighup,a <- sigterm", table.concat(log, ","))
end

--- A watcher that reports one change per `trigger()`.
local function fake_watchers()
  local pending, made = 0, 0
  return {
    trigger = function() pending = pending + 1 end,
    made = function() return made end,
    factory = function()
      made = made + 1
      return { wait = function() while pending == 0 do reactor.sleep(0.001) end; pending = pending - 1 end }
    end,
  }
end

function T:test_a_change_restarts_the_child()
  local log, children = {}, {}
  local signals, watchers = fake_signals(), fake_watchers()
  local code = run(function()
    reactor.fork(function()
      reactor.sleep(0.02); watchers.trigger()        -- the first child is replaced
      reactor.sleep(0.05); signals.send("sigterm")   -- the second ends the run
    end)
    return serve.supervise(reactor, {
      start = function()
        local child = fake_child(log, "c" .. (#children + 1), function(self) reactor.fork(function() reactor.sleep(0.005); self:exit(0) end) end)
        children[#children + 1] = child
        return child
      end,
      signals = signals,
      changes = watchers.factory,
      say = function() end,
    })
  end)
  self:assert_equal(0, code)
  self:assert_equal(2, #children)
  self:assert_equal("c1 <- sigterm,c2 <- sigterm", table.concat(log, ","))
  self:assert_equal(2, watchers.made())
end

function T:test_a_child_that_exits_in_watch_mode_waits_for_the_next_change()
  local log, children, said = {}, {}, {}
  local signals, watchers = fake_signals(), fake_watchers()
  local code = run(function()
    reactor.fork(function()
      reactor.sleep(0.02)
      children[1]:exit(3)                            -- the application crashes
      reactor.sleep(0.03); watchers.trigger()        -- a save brings it back
      reactor.sleep(0.03); signals.send("sigterm")
    end)
    return serve.supervise(reactor, {
      start = function()
        local child = fake_child(log, "c" .. (#children + 1), function(self) reactor.fork(function() self:exit(0) end) end)
        children[#children + 1] = child
        return child
      end,
      signals = signals,
      changes = watchers.factory,
      say = function(text) said[#said + 1] = text end,
    })
  end)
  self:assert_equal(0, code)
  self:assert_equal(2, #children)
  self:assert_true(said[1]:find("exited (3)", 1, true) ~= nil, said[1])
  -- A crash does not need a signal to the dead child.
  self:assert_equal("c2 <- sigterm", table.concat(log, ","))
end

function T:test_a_signal_while_waiting_after_a_crash_ends_the_run_with_the_code_of_the_child()
  local children = {}
  local signals, watchers = fake_signals(), fake_watchers()
  local code = run(function()
    reactor.fork(function() reactor.sleep(0.02); children[1]:exit(5); reactor.sleep(0.02); signals.send("sigint") end)
    return serve.supervise(reactor, {
      start = function() local child = fake_child({}, "c"); children[#children + 1] = child; return child end,
      signals = signals, changes = watchers.factory, say = function() end,
    })
  end)
  self:assert_equal(5, code)
  self:assert_equal(1, #children)
end

local function memory_fs(files)
  return {
    stat = function(path)
      local entry = files[path]
      if entry == nil then return nil end
      if type(entry) == "table" then return { type = "directory" } end
      return { type = "file", mtime = { sec = entry, nsec = 0 } }
    end,
    list = function(path)
      local names = {}
      for name in pairs(files[path]) do names[#names + 1] = { name = name } end
      table.sort(names, function(a, b) return a.name < b.name end)
      return names
    end,
  }
end

function T:test_a_snapshot_lists_lua_files_and_skips_hidden_directories()
  local files = {
    src = { app = true, ["notes.txt"] = true, [".cache"] = true },
    ["src/app"] = { ["init.lua"] = true },
    ["src/app/init.lua"] = 10, ["src/notes.txt"] = 11, ["src/.cache"] = { x = true }, ["src/.cache/x.lua"] = 12,
    ["main.lua"] = 20,
  }
  local snapshot = serve.snapshot(memory_fs(files), { "src", "main.lua", "missing" })
  self:assert_equal("10.0", snapshot["src/app/init.lua"])
  self:assert_equal("20.0", snapshot["main.lua"])
  self:assert_nil(snapshot["src/notes.txt"])
  self:assert_nil(snapshot["src/.cache/x.lua"])
end

function T:test_differs_sees_a_change_an_addition_and_a_removal()
  self:assert_false(serve.differs({ a = "1" }, { a = "1" }))
  self:assert_true(serve.differs({ a = "1" }, { a = "2" }))
  self:assert_true(serve.differs({ a = "1" }, { a = "1", b = "1" }))
  self:assert_true(serve.differs({ a = "1", b = "1" }, { a = "1" }))
end

function T:test_the_poller_returns_after_a_file_changes()
  local files = { src = { ["a.lua"] = true }, ["src/a.lua"] = 1 }
  local fs = memory_fs(files)
  local waited = run(function()
    local watcher = serve.poll_changes(reactor, fs, { "src" }, 0.01)
    reactor.fork(function() reactor.sleep(0.03); files["src/a.lua"] = 2 end)
    watcher:wait()
    return true
  end)
  self:assert_true(waited)
end

return T
