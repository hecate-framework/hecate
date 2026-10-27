-- Documented suspension matches behaviour (coding-standards.md, "Documentation in code";
-- testing.md, "Framework test policy"; finding A42).
--
-- `coroutine.yield` is instrumented: every call is counted per coroutine. Each case below runs
-- one public function of `hecate.reactor` on its normal path, inside a managed coroutine, in a
-- situation where the call has to wait (a rendezvous without a partner, a pending child, a
-- pending I/O request), and compares what it observed with the `---@async` tag found in the
-- source of the function. A function tagged `---@async` must be seen yielding; a function
-- without the tag must not yield, even when it is called here the way a caller would.
-- `deadline`, `scope` and `with_ambient`-like wrappers run a function: the body given to them
-- is the one that waits.
-- The scan of the sources also fails the test when a function tagged `---@async` has no case
-- and is not in `ALLOWLIST`, or when a case names a function that no longer exists.
local test = require("harness.test")
local uv = require("luv")
local reactor = require("hecate.reactor")
local T = test.Case("SuspensionTest")

local is_windows = package.config:sub(1, 1) == "\\"
local here = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
local source_directory = here:match("^(.*)/tests/unit/") .. "/src/hecate/reactor"

--- Tagged `---@async` but not exercised here: key -> why a case would not be cheap or reliable.
--- Empty on purpose: every suspending function of the package has a case. A function whose
--- suspension needs an event this test cannot provoke goes here, with its justification.
local ALLOWLIST = {}

--- The public functions of the package (top-level files, not `internal/`): key -> tagged async.
--- A key is `Class:method` (or `Class.function`) for a class, `<file>.<function>` otherwise.
---@return table<string, boolean>
local function annotated_functions()
  local listing = assert(uv.fs_scandir(source_directory))
  local functions = {}
  while true do
    local name, kind = uv.fs_scandir_next(listing)
    if not name then break end
    local stem = name:match("^(.+)%.lua$")
    if stem and kind ~= "directory" then
      local lines = {}
      for line in io.lines(source_directory .. "/" .. name) do lines[#lines + 1] = line end
      for i, line in ipairs(lines) do
        local receiver, separator, member = line:match("^function%s+([%w_]+)([.:])([%w_]+)%s*%(")
        if receiver and member:sub(1, 1) ~= "_" and receiver ~= "context" then
          local async, j = false, i - 1
          while j >= 1 and lines[j]:match("^%-%-%-") do
            if lines[j]:match("^%-%-%-@async%f[^%w_]") then async = true end
            j = j - 1
          end
          local key = (#receiver > 1 and receiver:match("^%u")) and (receiver .. separator .. member) or (stem .. "." .. member)
          functions[key] = async
        end
      end
    end
  end
  return functions
end

-- Instrumentation ------------------------------------------------------------------------------

local yields = setmetatable({}, { __mode = "k" }) -- coroutine -> number of yields seen
local real_yield = coroutine.yield

local function install()
  coroutine.yield = function(...)
    local running = coroutine.running()
    yields[running] = (yields[running] or 0) + 1
    return real_yield(...)
  end
end

local function uninstall() coroutine.yield = real_yield end

--- Runs `case(env)` on a fresh reactor with the real clock; the thunk it returns is the call under
--- observation. Returns whether the thunk yielded, or nil when the case skips itself.
local function observe(case)
  local observed
  reactor.run(function()
    local closers = {}
    local env = { defer = function(fn) closers[#closers + 1] = fn end }
    local ok, failure = pcall(function()
      local thunk = case(env)
      if not thunk then return end
      local me = coroutine.running()
      local before = yields[me] or 0
      thunk()
      observed = (yields[me] or 0) > before
    end)
    for i = #closers, 1, -1 do pcall(closers[i]) end
    if not ok then error(failure, 0) end
  end)
  return observed
end

-- Cases ----------------------------------------------------------------------------------------

local counter = 0
local function temporary_path()
  counter = counter + 1
  return ("%s/hecate-suspension-%d-%d"):format(uv.os_tmpdir(), uv.os_getpid(), counter)
end

local function lua_child(code, ...) return uv.exepath(), { "-e", code }, ... end

--- A future that completes after the caller suspended once.
local function later(value)
  return reactor.fork(function() reactor.sleep(0); return value end)
end

--- Connected loopback TCP streams: client, server, listener.
local function tcp_pair(env)
  local listener = reactor.listen_tcp("127.0.0.1", 0)
  env.defer(function() listener:close() end)
  local connecting = reactor.fork(reactor.connect_tcp, "127.0.0.1", listener:local_address().port)
  local server = listener:accept()
  env.defer(function() server:close() end)
  local client = connecting:value()
  env.defer(function() client:close() end)
  return client, server, listener
end

--- Two connected message-pipe peers in this process (Unix-domain socket pair), or nil on Windows.
local function peer_pair(env)
  if is_windows then return nil end
  local pair = assert(uv.socketpair("stream", 0, { nonblock = true }, { nonblock = true }))
  local a, b = uv.new_pipe(true), uv.new_pipe(true)
  assert(a:open(pair[1]))
  assert(b:open(pair[2]))
  local first, second = reactor.Peer(a), reactor.Peer(b)
  env.defer(function() first:close(); second:close() end)
  return first, second
end

local CASES = {
  -- Scheduler primitives.
  ["primitives.sleep"] = function() return function() reactor.sleep(0) end end,
  ["primitives.join"] = function() local f = later(1); return function() reactor.join(f) end end,
  ["primitives.select"] = function() local f = later(1); return function() reactor.select(f) end end,
  ["primitives.scope"] = function()
    return function() reactor.scope(function(scope) scope:fork(reactor.sleep, 0) end) end
  end,
  ["primitives.deadline"] = function()
    return function() reactor.deadline(30, function() reactor.sleep(0) end) end
  end,
  ["primitives.fork"] = function() return function() reactor.fork(function() end) end end,
  ["primitives.detach"] = function() return function() reactor.detach(function() end) end end,
  ["primitives.with_ambient"] = function()
    return function() reactor.with_ambient("key", 1, function() end) end -- suspends only if `fn` does
  end,
  ["primitives.ambient"] = function() return function() reactor.ambient("key") end end,
  ["primitives.now"] = function() return function() reactor.now() end end,
  ["Scope:fork"] = function()
    local scope
    reactor.fork(reactor.scope, function(open) scope = open; reactor.sleep(0.01) end)
    while not scope do reactor.sleep(0) end
    return function() scope:fork(function() end) end
  end,

  -- Futures, channels and synchronisation objects.
  ["Future:value"] = function() local f = later(1); return function() f:value() end end,
  ["Future:cancel"] = function() local f = later(1); return function() f:cancel() end end,
  ["Future:done"] = function() local f = later(1); return function() f:done() end end,
  ["Future:state"] = function() local f = later(1); return function() f:state() end end,
  ["Channel:send"] = function()
    local channel = reactor.Channel(0)
    reactor.fork(function() reactor.sleep(0); channel:receive() end)
    return function() channel:send(1) end
  end,
  ["Channel:receive"] = function()
    local channel = reactor.Channel(0)
    reactor.fork(function() reactor.sleep(0); channel:send(1) end)
    return function() channel:receive() end
  end,
  ["Channel:close"] = function() local channel = reactor.Channel(1); return function() channel:close() end end,
  ["Mutex:lock"] = function()
    local mutex = reactor.Mutex()
    local permit = mutex:lock()
    reactor.fork(function() reactor.sleep(0); permit:release() end)
    return function() mutex:lock():release() end
  end,
  ["Mutex:try_lock"] = function() local mutex = reactor.Mutex(); return function() mutex:try_lock():release() end end,
  ["Semaphore:acquire"] = function()
    local semaphore = reactor.Semaphore(0)
    reactor.fork(function() reactor.sleep(0); semaphore:release() end)
    return function() semaphore:acquire():release() end
  end,
  ["Semaphore:release"] = function() local semaphore = reactor.Semaphore(0); return function() semaphore:release() end end,
  ["Monitor:enter"] = function()
    local monitor = reactor.Monitor()
    reactor.fork(function() local held <close> = monitor:enter(); reactor.sleep(0.01) end) -- a monitor is not reentrant
    while not monitor:is_entered() do reactor.sleep(0) end
    return function() monitor:enter():release() end
  end,
  ["Monitor:condition"] = function() local monitor = reactor.Monitor(); return function() monitor:condition() end end,
  ["Condition:wait"] = function()
    local monitor = reactor.Monitor()
    local condition = monitor:condition()
    local permit = monitor:enter()
    reactor.fork(function()
      local inside <close> = monitor:enter() -- obtained while the waiter has left the monitor
      condition:notify()
    end)
    return function() condition:wait(); permit:release() end
  end,
  ["Condition:notify"] = function()
    local monitor = reactor.Monitor()
    local condition = monitor:condition()
    local permit = monitor:enter()
    return function() condition:notify(); permit:release() end
  end,
  ["Condition:broadcast"] = function()
    local monitor = reactor.Monitor()
    local condition = monitor:condition()
    local permit = monitor:enter()
    return function() condition:broadcast(); permit:release() end
  end,

  -- Signals, name resolution and file system.
  ["signal.wait_signal"] = function(env)
    if is_windows then return nil end -- Windows delivers only the console signals
    local guard = uv.new_signal() -- keeps an early signal from ending the process
    guard:start("sigusr1", function() end)
    env.defer(function() guard:close() end)
    local done = false
    reactor.fork(function()
      for _ = 1, 2000 do
        if done then return end
        uv.kill(uv.os_getpid(), "sigusr1")
        reactor.sleep(0.005)
      end
    end)
    return function() reactor.wait_signal("sigusr1"); done = true end
  end,
  ["dns.resolve"] = function() return function() reactor.resolve("localhost") end end,
  ["fs.write_file"] = function(env)
    local path = temporary_path()
    env.defer(function() uv.fs_unlink(path) end)
    return function() reactor.fs.write_file(path, "x") end
  end,
  ["fs.read_file"] = function(env)
    local path = temporary_path()
    env.defer(function() uv.fs_unlink(path) end)
    reactor.fs.write_file(path, "x")
    return function() reactor.fs.read_file(path) end
  end,
  ["fs.stat"] = function() return function() reactor.fs.stat(uv.os_tmpdir()) end end,
  ["fs.remove"] = function(env)
    local path = temporary_path()
    env.defer(function() uv.fs_unlink(path) end)
    reactor.fs.write_file(path, "x")
    return function() reactor.fs.remove(path) end
  end,
  ["fs.mkdir"] = function(env)
    local path = temporary_path()
    env.defer(function() uv.fs_rmdir(path) end)
    return function() reactor.fs.mkdir(path) end
  end,
  ["fs.rmdir"] = function(env)
    local path = temporary_path()
    env.defer(function() uv.fs_rmdir(path) end)
    reactor.fs.mkdir(path)
    return function() reactor.fs.rmdir(path) end
  end,
  ["fs.list"] = function(env)
    local path = temporary_path()
    env.defer(function() uv.fs_rmdir(path) end)
    reactor.fs.mkdir(path)
    return function() reactor.fs.list(path) end
  end,

  -- Processes and message pipes.
  ["process.run_process"] = function()
    return function() reactor.run_process(lua_child("os.exit(0)")) end
  end,
  ["process.spawn"] = function(env)
    return function()
      local process = reactor.spawn(lua_child("os.exit(0)"))
      env.defer(function() process:wait() end)
    end
  end,
  ["Process:wait"] = function()
    local process = reactor.spawn(lua_child("os.exit(0)"))
    return function() process:wait() end
  end,
  ["Process:kill"] = function(env)
    local process = reactor.spawn(lua_child("local t = os.clock() repeat until os.clock() - t > 5"))
    env.defer(function() process:wait() end)
    return function() process:kill() end
  end,
  ["Process:is_running"] = function(env)
    local process = reactor.spawn(lua_child("os.exit(0)"))
    env.defer(function() process:wait() end)
    return function() process:is_running() end
  end,
  ["ipc.parent"] = function() return function() reactor.ipc.parent() end end,
  ["Peer:send"] = function(env)
    local a = peer_pair(env)
    if not a then return nil end
    return function() a:send("x") end
  end,
  ["Peer:receive"] = function(env)
    local a, b = peer_pair(env)
    if not a then return nil end
    reactor.fork(function() reactor.sleep(0); a:send("x") end)
    return function() b:receive() end
  end,
  ["Peer:close"] = function(env)
    local a = peer_pair(env)
    if not a then return nil end
    return function() a:close() end
  end,

  -- Transport.
  ["tcp.connect_tcp"] = function(env)
    local listener = reactor.listen_tcp("127.0.0.1", 0)
    env.defer(function() listener:close() end)
    return function()
      local client = reactor.connect_tcp("127.0.0.1", listener:local_address().port)
      env.defer(function() client:close() end)
    end
  end,
  ["tcp.listen_tcp"] = function(env)
    return function()
      local listener = reactor.listen_tcp("127.0.0.1", 0)
      env.defer(function() listener:close() end)
    end
  end,
  ["TcpListener:accept"] = function(env)
    local listener = reactor.listen_tcp("127.0.0.1", 0)
    env.defer(function() listener:close() end)
    local port = listener:local_address().port
    reactor.fork(function()
      reactor.sleep(0)
      local client <close> = reactor.connect_tcp("127.0.0.1", port)
      reactor.sleep(0.01)
    end)
    return function() listener:accept():close() end
  end,
  ["TcpStream:read"] = function(env)
    local client, server = tcp_pair(env)
    reactor.fork(function() reactor.sleep(0); client:write("x") end)
    return function() server:read() end
  end,
  ["TcpStream:write"] = function(env)
    local client = tcp_pair(env)
    return function() client:write("x") end
  end,
  ["TcpStream:shutdown"] = function(env)
    local client = tcp_pair(env)
    return function() client:shutdown() end
  end,
  ["TcpStream:close"] = function(env)
    local client = tcp_pair(env)
    return function() client:close() end
  end,
  ["udp.bind_udp"] = function(env)
    return function()
      local socket = reactor.bind_udp("127.0.0.1", 0)
      env.defer(function() socket:close() end)
    end
  end,
  ["UdpSocket:send_to"] = function(env)
    local sender, receiver = reactor.bind_udp("127.0.0.1", 0), reactor.bind_udp("127.0.0.1", 0)
    env.defer(function() sender:close(); receiver:close() end)
    return function() sender:send_to("127.0.0.1", receiver:local_address().port, "x") end
  end,
  ["UdpSocket:receive_from"] = function(env)
    local sender, receiver = reactor.bind_udp("127.0.0.1", 0), reactor.bind_udp("127.0.0.1", 0)
    env.defer(function() sender:close(); receiver:close() end)
    local port = receiver:local_address().port
    reactor.fork(function() reactor.sleep(0); sender:send_to("127.0.0.1", port, "x") end)
    return function() receiver:receive_from() end
  end,
  ["pipe.connect_pipe"] = function(env)
    local path = is_windows and ("\\\\.\\pipe\\" .. temporary_path():match("[^/\\]+$")) or temporary_path()
    local listener = reactor.listen_pipe(path)
    env.defer(function() listener:close(); os.remove(path) end)
    return function()
      local client = reactor.connect_pipe(path)
      env.defer(function() client:close() end)
    end
  end,
  ["pipe.listen_pipe"] = function(env)
    local path = is_windows and ("\\\\.\\pipe\\" .. temporary_path():match("[^/\\]+$")) or temporary_path()
    return function()
      local listener = reactor.listen_pipe(path)
      env.defer(function() listener:close(); os.remove(path) end)
    end
  end,
}

-- Tests ----------------------------------------------------------------------------------------

function T:test_every_documented_suspension_is_observed_and_nothing_else_suspends()
  local annotated = annotated_functions()
  local failures = {}

  -- Coverage: a function tagged async needs a case or a justified allowlist entry.
  for key, async in pairs(annotated) do
    if async and not CASES[key] and not ALLOWLIST[key] then
      failures[#failures + 1] = key .. " is tagged ---@async but this test has no case for it"
    end
  end
  for key, reason in pairs(ALLOWLIST) do
    if not annotated[key] then failures[#failures + 1] = "allowlist entry " .. key .. " names no tagged function" end
    if type(reason) ~= "string" or reason == "" then failures[#failures + 1] = "allowlist entry " .. key .. " has no reason" end
    if CASES[key] then failures[#failures + 1] = key .. " has a case and an allowlist entry: drop the entry" end
  end
  for key in pairs(CASES) do
    if annotated[key] == nil then failures[#failures + 1] = "case " .. key .. " names no public function of the sources" end
  end

  -- Behaviour: observed yield against the tag.
  install()
  local ok, problem = pcall(function()
    local keys = {}
    for key in pairs(CASES) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
      if annotated[key] ~= nil then
        local observed = observe(CASES[key])
        if observed == nil then
          print("SKIP " .. key .. ": not available on this platform")
        elseif annotated[key] and not observed then
          failures[#failures + 1] = key .. " is tagged ---@async but was never seen to yield"
        elseif not annotated[key] and observed then
          failures[#failures + 1] = key .. " yielded but is not tagged ---@async"
        end
      end
    end
  end)
  uninstall()
  if not ok then error(problem, 0) end

  if #failures > 0 then
    table.sort(failures)
    self:fail("documented suspension does not match behaviour:\n  " .. table.concat(failures, "\n  "))
  end
end

return T
