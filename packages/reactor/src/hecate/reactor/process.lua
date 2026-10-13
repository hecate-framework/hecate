-- Child processes as a suspending call over libuv (concurrency.md; reactor README).
global <const> type, error, require, table, pcall, tostring

local core = require("hecate.core")
local uv = require("luv")
local uv_call = require("hecate.reactor.internal.uv_call")
local context = require("hecate.reactor.internal.context")

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

return M
