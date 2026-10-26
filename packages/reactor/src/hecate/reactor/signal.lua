-- Signals as a suspending call over libuv signal handles (concurrency.md, "Signals and
-- shutdown"). The handle exists only while a coroutine waits and is closed when it resumes.
global <const> type, error, require, pcall, tostring

local core = require("hecate.core")
local uv = require("luv")
local uv_call = require("hecate.reactor.internal.uv_call")
local context = require("hecate.reactor.internal.context")

-- Documented on `hecate.reactor` (module class completed here so that the LuaLS export lists the
-- function; coding-standards.md, "Annotations for the reference").

---@class hecate.reactor
local M = {}

--- Suspends until one of the named signals is delivered; returns its name. Names are libuv
--- names such as "sigint", "sigterm" and "sighup"; Windows delivers only the console ones.
---
--- Raises `hecate.core.ArgumentError` for no name or a name that is not a string, and
--- `hecate.core.CancellationError` if the enclosing scope is cancelled while waiting.
---@async
---@param ... string  the names of the signals to wait for
---@return string name  the name of the signal delivered
function M.wait_signal(...)
  local names = { ... }
  if #names == 0 then error(core.ArgumentError("reactor.wait_signal: expects at least one signal name"), 2) end
  for i = 1, #names do
    if type(names[i]) ~= "string" then
      error(core.ArgumentError("reactor.wait_signal: signal names must be strings"), 2)
    end
  end
  uv_call.begin("wait_signal")
  local handles = {}
  local ok, name = pcall(context.suspend, function(wake)
    for i = 1, #names do
      local handle = uv.new_signal()
      handles[#handles + 1] = handle
      -- luv raises (instead of returning nil) for a name the platform does not know.
      local called, started, err = pcall(handle.start, handle, names[i], function(received) wake(received) end)
      if not called then started, err = nil, started end
      if not started then
        for j = 1, #handles do handles[j]:close() end
        handles = {}
        uv_call.fail("wait_signal", tostring(err))
      end
    end
    return function()
      for i = 1, #handles do if not handles[i]:is_closing() then handles[i]:close() end end
    end
  end)
  if not ok then error(name, 0) end
  return name
end

return M
