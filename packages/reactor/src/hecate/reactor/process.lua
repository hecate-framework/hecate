-- Child processes as a suspending call over libuv (concurrency.md; reactor README).
global <const> type, error, require, table, pcall, tostring, pairs, ipairs, package

local core = require("hecate.core")
local uv = require("luv")
local uv_call = require("hecate.reactor.internal.uv_call")
local context = require("hecate.reactor.internal.context")
local ipc = require("hecate.reactor.ipc")
local environment_of = require("hecate.reactor.internal.environment")

local IS_WINDOWS = package.config:sub(1, 1) == "\\"

--- The environment of a child as `NAME=value` entries: the inherited one plus `added`, without the
--- marker of this process's own message pipe (a child must not believe it owns that pipe: only
--- `ipc = true` sets it, through `added`). Windows names compare without regard to case.
---@param added table<string, string>
---@return string[]
local function environment(added)
  local marker = ipc.child_marker()
  return environment_of.merge(uv.os_environ(), added, IS_WINDOWS, marker)
end

--- A child that is not meant to reach this process's own message pipe would inherit its
--- descriptor (fd 3, Unix). The returned pipe takes that place in the child's descriptors; the
--- caller closes it once the child started, which leaves the child an end that reads as closed.
---@param stdio table  the `stdio` option, completed here
---@return table? guard  to close after the spawn, nil when not needed
local function guard_descriptor(stdio)
  if stdio[4] ~= nil or not ipc.holds_descriptor() then return nil end
  local guard = uv.new_pipe(false)
  stdio[4] = guard
  return guard
end

-- Documented on `hecate.reactor` (module class completed here so that the LuaLS export lists the
-- function; coding-standards.md, "Annotations for the reference").

---@class hecate.reactor
local M = {}

--- The outcome of a child process: exit status, terminating signal and captured output.
---@class hecate.reactor.ProcessResult
---@field code integer  exit status; on Windows 1 for a child ended by `kill`
---@field signal integer  terminating signal, 0 if none (always 0 on Windows: detect a crash by `code` there)
---@field stdout string
---@field stderr string

--- Runs a program to completion, capturing its output. The child is terminated (SIGKILL; on
--- Windows `TerminateProcess`) if the caller is cancelled: cancellation is the way to stop it, not
--- `Process:kill`. `args` excludes the program name. The child inherits the environment of this
--- process, without the marker of its own message pipe, and does not inherit that pipe.
---
--- Raises `hecate.core.ArgumentError` if `program` is not a string, and
--- `hecate.reactor.IoError` if the program cannot be started.
---@async
---@param program string  the program to run
---@param args? string[]  its arguments, without the program name
---@return hecate.reactor.ProcessResult result  the exit status and the captured output
function M.run_process(program, args)
  if type(program) ~= "string" then
    error(core.ArgumentError(("reactor.run_process: expects a program name, got %s"):format(type(program))), 2)
  end
  uv_call.begin("reactor.run_process")
  local out, err = uv.new_pipe(false), uv.new_pipe(false)
  local chunks = { out = {}, err = {} }
  local process
  local pending = 3 -- exit, stdout end, stderr end
  local exit_code, exit_signal
  local wake_main
  local function done()
    pending = pending - 1
    if pending == 0 and wake_main then wake_main() end
  end
  local function reader(pipe, key)
    pipe:read_start(function(e, data)
      if e then data = nil end
      if data then
        chunks[key][#chunks[key] + 1] = data
      else
        pipe:read_stop()
        if not pipe:is_closing() then pipe:close() end
        done()
      end
    end)
  end
  local stdio = { nil, out, err }
  local guard = guard_descriptor(stdio)
  local spawned, pid = uv["spawn"](program, { args = args or {}, env = environment({}), stdio = stdio },
    function(code, signal)
      exit_code, exit_signal = code, signal
      if process and not process:is_closing() then process:close() end
      done()
    end)
  if guard then guard:close() end
  if not spawned then
    out:close(); err:close()
    uv_call.fail("reactor.run_process", "start " .. program, tostring(pid))
  end
  process = spawned
  reader(out, "out"); reader(err, "err")
  local ok, failure = pcall(context.suspend, function(wake)
    wake_main = wake
    if pending == 0 then wake() end
    return function() wake_main = nil end
  end)
  if not ok then
    -- Cancelled: stop the child and let its handles close.
    if exit_code == nil and process and not process:is_closing() then process:kill("sigkill") end
    if not out:is_closing() then out:close() end
    if not err:is_closing() then err:close() end
    error(failure, 0)
  end
  return { code = exit_code, signal = exit_signal, stdout = table.concat(chunks.out), stderr = table.concat(chunks.err) }
end

--- A long-lived child process started by `reactor.spawn`.
---@class hecate.reactor.Process
---@field pid integer  operating-system process identifier
---@field ipc? hecate.reactor.Peer  the message pipe to the child, when started with `ipc = true`
---@overload fun(handle: table, pid: integer, peer?: hecate.reactor.Peer): hecate.reactor.Process
local Process = core.class("Process")

---@param handle table  the libuv process handle
---@param pid integer
---@param peer? hecate.reactor.Peer
---@private
function Process:init(handle, pid, peer)
  self._handle = handle
  self.pid = pid
  self.ipc = peer
  self._result = nil -- { code, signal } once the child exited
  self._waiting = {}
end

--- Records the exit and wakes every coroutine in `wait`.
---@param code integer
---@param signal integer
---@private
function Process:_exited(code, signal)
  self._result = { code = code, signal = signal }
  if not self._handle:is_closing() then self._handle:close() end
  local waiting = self._waiting
  self._waiting = {}
  for _, wake in ipairs(waiting) do wake() end
end

--- Suspends until the child exits. Several coroutines may wait. Cancelling a wait leaves the
--- child running. Returns at once for a child that already exited.
---
--- On Windows a child ended by `kill` reports `code` 1 and `signal` 0: there, a crash or a kill is
--- recognised by `code` alone; `signal` is only meaningful on Unix.
---@async
---@return { code: integer, signal: integer } status  exit status and terminating signal (0 if none)
function Process:wait()
  uv_call.begin("reactor.Process.wait")
  while self._result == nil do
    context.suspend(function(wake)
      local list = self._waiting
      list[#list + 1] = wake
      return function()
        for index, entry in ipairs(self._waiting) do
          if entry == wake then table.remove(self._waiting, index); break end
        end
      end
    end)
  end
  return { code = self._result.code, signal = self._result.signal }
end

--- Sends a signal to the child (default `"sigterm"`; `"sigkill"` cannot be caught). Does nothing for
--- a child that already exited, and treats a child that vanished meanwhile (`ESRCH`) as success.
--- Does not suspend. This is a signal operation, not the cancellation mechanism: cancelling the
--- coroutine that waits (`reactor.scope`, `reactor.deadline`) leaves the child running.
---
--- Windows supports only `SIGTERM`, `SIGKILL`, `SIGINT` and `0` (does the process exist?); the
--- first three end the process at once, with no chance to clean up, and any other signal fails
--- with `ENOSYS`.
---
--- Raises `hecate.reactor.IoError` when the signal is not valid or cannot be delivered.
---@param signal? string|integer  signal name (`"sigterm"`) or number, default `"sigterm"`
function Process:kill(signal)
  if self._result ~= nil or self._handle:is_closing() then return end
  -- luv raises a Lua error for an unknown signal name: report it like libuv's EINVAL.
  local called, ok, err = pcall(self._handle.kill, self._handle, signal or "sigterm")
  if not called then uv_call.fail("reactor.Process.kill", "kill", "EINVAL: invalid signal (" .. tostring(ok) .. ")") end
  if not ok then
    if tostring(err):match("^ESRCH") then return end
    uv_call.fail("reactor.Process.kill", "kill", tostring(err))
  end
end

--- Returns whether the child is still running.
---@return boolean
function Process:is_running() return self._result == nil end

core.finalise(Process)

--- Options of `reactor.spawn`.
---@class hecate.reactor.SpawnOptions
---@field env? table<string, string>  variables added to the inherited environment
---@field cwd? string  working directory of the child
---@field ipc? boolean  open a message pipe to the child (`Process.ipc`; `hecate.reactor.ipc.parent()` in the child)
---@field stdout? "inherit"|"ignore"  default "inherit"
---@field stderr? "inherit"|"ignore"  default "inherit"

local PROCESS_KEYS = { env = true, cwd = true, ipc = true, stdout = true, stderr = true }

---@param options any
---@return table
local function check_start_options(options)
  if options == nil then return {} end
  if type(options) ~= "table" then
    error(core.ArgumentError(("reactor.spawn: expects an options table, got %s"):format(type(options))), 3)
  end
  for key in pairs(options) do
    if not PROCESS_KEYS[key] then error(core.ArgumentError(("reactor.spawn: unknown option %s"):format(tostring(key))), 3) end
  end
  if options.ipc ~= nil and type(options.ipc) ~= "boolean" then
    error(core.ArgumentError("reactor.spawn: option ipc must be a boolean"), 3)
  end
  if options.cwd ~= nil and type(options.cwd) ~= "string" then
    error(core.ArgumentError("reactor.spawn: option cwd must be a string"), 3)
  end
  for _, key in ipairs({ "stdout", "stderr" }) do
    local value = options[key]
    if value ~= nil and value ~= "inherit" and value ~= "ignore" then
      error(core.ArgumentError(("reactor.spawn: option %s must be \"inherit\" or \"ignore\""):format(key)), 3)
    end
  end
  if options.env ~= nil then
    if type(options.env) ~= "table" then error(core.ArgumentError("reactor.spawn: option env must be a table"), 3) end
    for name, value in pairs(options.env) do
      if type(name) ~= "string" or name == "" or name:find("=", 1, true) or type(value) ~= "string" then
        error(core.ArgumentError("reactor.spawn: option env maps variable names to strings"), 3)
      end
    end
  end
  return options
end

--- Starts a program and returns at once: a long-lived child, unlike `run_process`, which runs one
--- to completion. The standard output and error are inherited by default. With `ipc = true` the
--- child gets a message pipe (`process.ipc`; the child reaches it with
--- `hecate.reactor.ipc.parent()`); only that child holds it: a process it starts in turn neither
--- inherits the pipe nor the environment marker (also when started through `run_process`).
--- The caller owns the child: it must `wait` for it or `kill` it, and close `process.ipc` when done
--- (messages the child sent before exiting stay readable until then). A running child keeps the
--- libuv loop alive, so waiting for it with no other work pending is not a deadlock; `reactor.run`
--- returns when its main coroutine ends, whether or not a child still runs. `args` excludes the
--- program name.
---
--- The child inherits the environment with `env` added (names are case-insensitive on Windows).
--- Windows: a program is looked up like libuv does (the working directory first, then `PATH`; a
--- relative `program` therefore depends on `cwd`), a `.cmd` or `.bat` script is not found without
--- its extension and cannot be started this way (run `cmd.exe /c script`), and `"inherit"` needs
--- valid standard output and error in this process (a service without them gets a failure from
--- the operating system: pass `"ignore"`).
---
--- Raises `hecate.core.ArgumentError` for a malformed argument or option and
--- `hecate.reactor.IoError` if the program cannot be started.
---@param program string  the program to start
---@param args? string[]  its arguments, without the program name
---@param options? hecate.reactor.SpawnOptions
---@return hecate.reactor.Process process  the running child
function M.spawn(program, args, options) -- glossary-ok: starts an operating-system process (ADR 0023), not a coroutine
  if type(program) ~= "string" or program == "" then
    error(core.ArgumentError(("reactor.spawn: expects a program name, got %s"):format(tostring(program))), 2)
  end
  if args ~= nil and type(args) ~= "table" then
    error(core.ArgumentError(("reactor.spawn: expects an argument list, got %s"):format(type(args))), 2)
  end
  options = check_start_options(options)
  uv_call.begin("reactor.spawn")
  local added = options.env or {}
  local ipc_pipe
  if options.ipc then
    ipc_pipe = uv.new_pipe(true)
    local name, value = ipc.child_marker()
    added = { [name] = value }
    for key, entry in pairs(options.env or {}) do added[key] = entry end
  end
  -- luv takes the number of entries from the largest integer key and maps an absent entry to
  -- "ignore" and an integer to "inherit that descriptor". The table is built key by key: a
  -- constructor with nil holes would depend on the border of the table.
  local stdio = {}
  if options.stdout ~= "ignore" then stdio[2] = 1 end
  if options.stderr ~= "ignore" then stdio[3] = 2 end
  stdio[4] = ipc_pipe
  local guard = guard_descriptor(stdio)
  local state = {}
  local spawned, pid = uv["spawn"](program, {
    args = args or {},
    env = environment(added),
    cwd = options.cwd,
    stdio = stdio,
  }, function(code, signal)
    ---@diagnostic disable-next-line: invisible  -- same class, reached through the callback state
    if state.process then state.process:_exited(code, signal) end
  end)
  if guard then guard:close() end
  if not spawned then
    if ipc_pipe then ipc_pipe:close() end
    uv_call.fail("reactor.spawn", "start " .. program, tostring(pid))
  end
  local process = Process(spawned, pid --[[@as integer]], ipc_pipe and ipc.Peer(ipc_pipe) or nil)
  state.process = process
  return process
end

---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
M.Process = Process

return M
