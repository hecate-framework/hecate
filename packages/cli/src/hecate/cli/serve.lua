-- The supervision of `hecate serve` (OQ-132): the project runs in a child process, and this process forwards the signals
-- it receives, returns the exit code of the child and, with `--watch`, restarts the child when a source file changes.
-- The reactor, the child and the signal watcher are passed in, so the logic is tested without a real server.
global <const> table, ipairs, pairs, pcall, type, string, math, tostring

--- The reactor functions the supervision uses (`hecate.reactor` provides them).
---@class hecate.cli.ServeReactor
---@field scope function  `scope(fn)`: runs `fn(scope)` and returns when its children are done
---@field select function  `select(f1, ...)`: the index and value of the first future to finish
---@field sleep function  `sleep(seconds)`
---@field deadline function  `deadline(seconds, fn, ...)`: raises when `fn` is late

---@class hecate.cli.ServeChild
---@field wait fun(self: hecate.cli.ServeChild): { code: integer, signal: integer }  suspends until the child exits
---@field kill fun(self: hecate.cli.ServeChild, signal?: string)

---@class hecate.cli.ServeOptions
---@field start fun(): hecate.cli.ServeChild  starts the project
---@field signals { wait: fun(self: table): string }  the signals to forward (`sigint`, `sigterm`, `sighup`)
---@field changes? fun(): { wait: fun(self: table) }  a watcher of the sources, made at each start (`--watch`); `wait` returns when something changed
---@field shared_console? boolean  the child receives Ctrl+C from the console on its own (Windows, where every process of the console gets it, and `kill` is `TerminateProcess`): `sigint` and `sigterm` are not forwarded, the child gets `grace` seconds, then it is killed
---@field grace? number  seconds a child gets to stop after `sigterm` before `sigkill` (default 10)
---@field say? fun(text: string)  progress messages (standard error)

--- Supervising the project process.
---@class hecate.cli.serve
local M = {}

--- The exit code of this process for the status of the child: its exit code, `128 + n` when a signal ended it.
---@param status { code: integer, signal: integer }
---@return integer code
function M.exit_code(status)
  if status.signal and status.signal ~= 0 then return 128 + status.signal end
  return status.code or 1
end

--- Stops a child: sends `signal`, waits for it to exit for `grace` seconds, then kills it.
---@param reactor table  the reactor: the functions of `hecate.cli.ServeReactor`
---@param child hecate.cli.ServeChild
---@param signal string
---@param grace number
---@param forward? boolean  default true; false: the child already got the signal from the console
---@return { code: integer, signal: integer } status
local function stop(reactor, child, signal, grace, forward)
  if forward ~= false then child:kill(signal) end
  local ok, status = pcall(reactor.deadline, grace, function() return child:wait() end)
  if ok then return status end
  child:kill("sigkill")
  return child:wait()
end

--- Runs the project until it exits (without `changes`), or until a signal ends it. Returns the exit code of this process.
---
--- A `sigint` or `sigterm` is forwarded to the child, which gets `grace` seconds; `sighup` is forwarded and the child keeps
--- running (a primary reloads, ADR 0023). With `changes`, a change of the sources stops the child (as for `sigterm`) and
--- starts it again; a child that exits by itself is waited for: it starts again at the next change.
---@async
---@param reactor table  the reactor: the functions of `hecate.cli.ServeReactor`
---@param options hecate.cli.ServeOptions
---@return integer exit_code
function M.supervise(reactor, options)
  local grace = options.grace or 10
  local say = options.say or function() end
  -- `select` cancels the futures that lose, and a signal that arrived at the same moment as the winner would be lost with
  -- the value of its future: the future that waits for a signal records it here before it finishes.
  local pending = {}
  local function wait_signal()
    local name = options.signals:wait()
    pending[#pending + 1] = name
    return name
  end
  --- The next signal that ends the run (`sigint`, `sigterm`), forwarding `sighup` to `child` on the way; nil when none.
  local function ending_signal(child)
    while #pending > 0 do
      local name = table.remove(pending, 1)
      if name == "sighup" then
        if child and not options.shared_console then child:kill("sighup") end
      else
        return name
      end
    end
    return nil
  end

  return reactor.scope(function(scope)
    while true do
      local child = options.start()
      local watcher = options.changes and options.changes() or nil
      local outcome, detail

      while true do
        local futures = {
          scope:fork(function() return child:wait() end),
          scope:fork(wait_signal),
        }
        if watcher then futures[3] = scope:fork(function() watcher:wait() return "change" end) end
        local index, value = reactor.select(table.unpack(futures))
        local ending = ending_signal(child)
        if ending then
          outcome, detail = "signal", ending
          break
        elseif index == 1 then
          outcome, detail = "exited", value
          break
        elseif index == 3 then
          outcome = "change"
          break
        end
      end

      if outcome == "signal" then
        return M.exit_code(stop(reactor, child, detail, grace, not options.shared_console))
      elseif outcome == "exited" then
        if not watcher then return M.exit_code(detail) end
        say(string.format("the application exited (%d); waiting for a change of the sources", M.exit_code(detail)))
        -- Wait for a change, or for a signal that ends the wait.
        while true do
          local index = reactor.select(
            scope:fork(function() watcher:wait() return "change" end),
            scope:fork(wait_signal))
          if ending_signal(nil) then return M.exit_code(detail) end
          if index == 1 then break end
        end
      else
        say("a source changed: restarting")
        stop(reactor, child, "sigterm", grace)
      end
    end
  end)
end

--- Whether two snapshots (path to modification time) differ.
---@param before table<string, string>
---@param after table<string, string>
---@return boolean changed
function M.differs(before, after)
  for path, stamp in pairs(before) do
    if after[path] ~= stamp then return true end
  end
  for path in pairs(after) do
    if before[path] == nil then return true end
  end
  return false
end

---@class hecate.cli.WatchFileSystem
---@field stat fun(path: string): table?
---@field list fun(path: string): { name: string, type: string }[]

--- A snapshot of the files under `roots` (a file, or a directory searched without the hidden directories): the
--- modification time of each `.lua` file.
---@param file_system hecate.cli.WatchFileSystem
---@param roots string[]
---@return table<string, string> snapshot
function M.snapshot(file_system, roots)
  local result = {}
  local function stamp(path)
    local status = file_system.stat(path)
    if not status then return nil end
    local mtime = status.mtime
    if type(mtime) == "table" then return tostring(mtime.sec) .. "." .. tostring(mtime.nsec) end
    return tostring(mtime)
  end
  local function visit(path, depth)
    local status = file_system.stat(path)
    if not status then return end
    if status.type == "directory" then
      if depth > 12 then return end
      for _, entry in ipairs(file_system.list(path)) do
        if entry.name:sub(1, 1) ~= "." then visit(path .. "/" .. entry.name, depth + 1) end
      end
    elseif path:match("%.lua$") then
      result[path] = stamp(path)
    end
  end
  for _, root in ipairs(roots) do visit(root, 0) end
  return result
end

--- A watcher of the sources that polls: `wait` returns once a file has been added, removed or modified since the
--- snapshot taken when the watcher was made (or at the previous change), after a short pause so that a save that writes
--- several files counts once. Polling works the same on every platform.
---@param reactor table  the reactor: the functions of `hecate.cli.ServeReactor`
---@param file_system hecate.cli.WatchFileSystem
---@param roots string[]
---@param interval? number  seconds between two looks (default 0.5)
---@return { wait: fun(self: table) }
function M.poll_changes(reactor, file_system, roots, interval)
  interval = interval or 0.5
  local known = M.snapshot(file_system, roots)
  return {
    wait = function()
      while true do
        reactor.sleep(interval)
        local current = M.snapshot(file_system, roots)
        if M.differs(known, current) then
          reactor.sleep(math.min(interval, 0.2))
          known = M.snapshot(file_system, roots)
          return
        end
      end
    end,
  }
end

return M
