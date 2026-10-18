-- Child processes as a suspending call over libuv (concurrency.md; reactor README).
global <const> type, error, require, table, pcall, tostring, pairs, ipairs

local core = require("hecate.core")
local uv = require("luv")
local uv_call = require("hecate.reactor.internal.uv_call")
local context = require("hecate.reactor.internal.context")
local ipc = require("hecate.reactor.ipc")

-- Documented on `hecate.reactor` (module class completed here so that the LuaLS export lists the
-- function; coding-standards.md, "Annotations for the reference").

---@class hecate.reactor
local M = {}

--- The outcome of a child process: exit status, terminating signal and captured output.
---@class hecate.reactor.ProcessResult
---@field code integer  exit status
---@field signal integer  terminating signal, 0 if none
---@field stdout string
---@field stderr string

--- Runs a program to completion, capturing its output. The child is killed if the caller
--- is cancelled. `args` excludes the program name.
---
--- Raises `hecate.core.ArgumentError` if `program` is not a string, and
--- `hecate.reactor.IoError` if the program cannot be started.
---@async
---@param program string  the program to run
---@param args? string[]  its arguments, without the program name
---@return hecate.reactor.ProcessResult result  the exit status and the captured output
function M.run_process(program, args)
  if type(program) ~= "string" then
    error(core.ArgumentError(("run expects a program name, got %s"):format(type(program))), 2)
  end
  uv_call.begin("run")
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
  local spawned, pid = uv["spawn"](program, { args = args or {}, stdio = { nil, out, err } },
    function(code, signal)
      exit_code, exit_signal = code, signal
      if process and not process:is_closing() then process:close() end
      done()
    end)
  if not spawned then
    out:close(); err:close()
    uv_call.fail("start " .. program, tostring(pid))
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
---@field ipc? hecate.reactor.Peer  the channel to the child, when started with `ipc = true`
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
---@async
---@return { code: integer, signal: integer } status  exit status and terminating signal (0 if none)
function Process:wait()
  uv_call.begin("wait")
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

--- Sends a signal to the child (default `"sigterm"`; `"sigkill"` cannot be caught). On Windows
--- every signal ends the process, with no chance to clean up. Does nothing for a child that
--- already exited. Does not suspend.
---
--- Raises `hecate.reactor.IoError` when the signal cannot be delivered.
---@param signal? string|integer  signal name or number
function Process:kill(signal)
  if self._result ~= nil or self._handle:is_closing() then return end
  local ok, err = self._handle:kill(signal or "sigterm")
  if not ok then uv_call.fail("kill", tostring(err)) end
end

--- Returns whether the child is still running.
---@return boolean
function Process:is_running() return self._result == nil end

core.finalise(Process)

--- Options of `reactor.spawn`.
---@class hecate.reactor.SpawnOptions
---@field env? table<string, string>  variables added to the inherited environment
---@field cwd? string  working directory of the child
---@field ipc? boolean  open a message channel to the child (`Process.ipc`; `hecate.reactor.ipc.parent()` in the child)
---@field stdout? "inherit"|"ignore"  default "inherit"
---@field stderr? "inherit"|"ignore"  default "inherit"

local PROCESS_KEYS = { env = true, cwd = true, ipc = true, stdout = true, stderr = true }

---@param options any
---@return table
local function check_start_options(options)
  if options == nil then return {} end
  if type(options) ~= "table" then
    error(core.ArgumentError(("spawn expects an options table, got %s"):format(type(options))), 3)
  end
  for key in pairs(options) do
    if not PROCESS_KEYS[key] then error(core.ArgumentError(("spawn: unknown option %s"):format(tostring(key))), 3) end
  end
  if options.ipc ~= nil and type(options.ipc) ~= "boolean" then
    error(core.ArgumentError("spawn: option ipc must be a boolean"), 3)
  end
  if options.cwd ~= nil and type(options.cwd) ~= "string" then
    error(core.ArgumentError("spawn: option cwd must be a string"), 3)
  end
  for _, key in ipairs({ "stdout", "stderr" }) do
    local value = options[key]
    if value ~= nil and value ~= "inherit" and value ~= "ignore" then
      error(core.ArgumentError(("spawn: option %s must be \"inherit\" or \"ignore\""):format(key)), 3)
    end
  end
  if options.env ~= nil then
    if type(options.env) ~= "table" then error(core.ArgumentError("spawn: option env must be a table"), 3) end
    for name, value in pairs(options.env) do
      if type(name) ~= "string" or name == "" or name:find("=", 1, true) or type(value) ~= "string" then
        error(core.ArgumentError("spawn: option env maps variable names to strings"), 3)
      end
    end
  end
  return options
end

--- The environment of the child as `NAME=value` entries: the inherited one plus `added`.
---@param added table<string, string>
---@return string[]
local function environment(added)
  local merged = uv.os_environ()
  for name, value in pairs(added) do merged[name] = value end
  local list = {}
  for name, value in pairs(merged) do list[#list + 1] = name .. "=" .. value end
  table.sort(list)
  return list
end

--- Starts a program and returns at once: a long-lived child, unlike `run_process`, which runs one
--- to completion. The standard output and error are inherited by default. With `ipc = true` the
--- child gets a message channel (`process.ipc`; the child reaches it with
--- `hecate.reactor.ipc.parent()`). The caller owns the child: it must `wait` for it or `kill` it,
--- and close `process.ipc` when done (messages the child sent before exiting stay readable until then).
--- A running child keeps the reactor alive. `args` excludes the program name.
---
--- Raises `hecate.core.ArgumentError` for a malformed argument or option and
--- `hecate.reactor.IoError` if the program cannot be started.
---@param program string  the program to start
---@param args? string[]  its arguments, without the program name
---@param options? hecate.reactor.SpawnOptions
---@return hecate.reactor.Process process  the running child
function M.spawn(program, args, options) -- glossary-ok: starts an operating-system process (ADR 0023), not a coroutine
  if type(program) ~= "string" or program == "" then
    error(core.ArgumentError(("spawn expects a program name, got %s"):format(tostring(program))), 2)
  end
  if args ~= nil and type(args) ~= "table" then
    error(core.ArgumentError(("spawn expects an argument list, got %s"):format(type(args))), 2)
  end
  options = check_start_options(options)
  uv_call.begin("spawn")
  local added = options.env or {}
  local channel
  if options.ipc then
    channel = uv.new_pipe(true)
    local name, value = ipc.child_marker()
    added = { [name] = value }
    for key, entry in pairs(options.env or {}) do added[key] = entry end
  end
  local state = {}
  local spawned, pid = uv["spawn"](program, {
    args = args or {},
    env = environment(added),
    cwd = options.cwd,
    stdio = {
      nil,
      options.stdout == "ignore" and nil or 1,
      options.stderr == "ignore" and nil or 2,
      channel,
    },
  }, function(code, signal)
    ---@diagnostic disable-next-line: invisible  -- same class, reached through the callback state
    if state.process then state.process:_exited(code, signal) end
  end)
  if not spawned then
    if channel then channel:close() end
    uv_call.fail("start " .. program, tostring(pid))
  end
  local process = Process(spawned, pid --[[@as integer]], channel and ipc.Peer(channel) or nil)
  state.process = process
  return process
end

---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
M.Process = Process

return M
