-- `reactor.offload`: runs a self-contained Lua function on libuv's thread pool, in the Lua state
-- of a pool thread, and suspends the caller until it returns (concurrency.md, "Offload"; OQ-27,
-- OQ-119). The basis is luv's `new_work`/`queue_work`, used unmodified (OQ-1). luv passes at most
-- nine scalar values each way and swallows an error of the work function, so arguments and
-- results travel as one string encoded by `internal/transfer`, and `work` below catches and
-- reports the error itself.
global <const> type, error, require, pcall, xpcall, tostring, debug, load, table, string, select

local core = require("hecate.core")
local uv = require("luv")
local uv_call = require("hecate.reactor.internal.uv_call")
local context = require("hecate.reactor.internal.context")
local transfer = require("hecate.reactor.internal.transfer")

local OffloadError = core.error_class("OffloadError", "hecate.reactor.OffloadError", core.Error)

--- Runs on a pool thread. Sent as bytecode by luv, so it has no upvalue but `_ENV` (the global
--- table of the pool thread's state); every value it needs arrives as an argument. Returns
--- `id, "ok", encoded results` or `id, "error", message, traceback`.
---@param id integer
---@param codec_code string  bytecode of `transfer.factory`
---@param fn_code string  bytecode of the offloaded function
---@param payload string  the encoded arguments
---@return integer id
---@return string status
---@return string data
---@return string? traceback
local function work(id, codec_code, fn_code, payload)
  local key = "hecate.reactor.offload.codec" -- a literal: `work` may not capture an upvalue
  local registry = debug.getregistry()
  local cached = registry[key]
  if cached == nil or cached.code ~= codec_code then
    local factory = load(codec_code, "=hecate.reactor.offload codec", "b") --[[@as function]]
    cached = { code = codec_code, codec = factory() }
    registry[key] = cached
  end
  local codec = cached.codec
  local fn, load_error = load(fn_code, "=offload", "b")
  if fn == nil then return id, "error", "cannot load the function: " .. tostring(load_error), "" end
  local n, args = codec.decode(payload)
  local function handler(err)
    local message
    if type(err) == "table" and type(err.message) == "string" then
      message = err.message
    else
      local ok, text = pcall(tostring, err)
      message = ok and type(text) == "string" and text or "(an error that cannot be converted to a string)"
    end
    return { message = message, traceback = debug.traceback(message, 2) }
  end
  local results = table.pack(xpcall(fn, handler, table.unpack(args, 1, n)))
  if not results[1] then return id, "error", results[2].message, results[2].traceback end
  local ok, encoded = pcall(codec.encode, "result", results.n - 1, results, 2)
  if not ok then return id, "error", tostring(encoded), "" end
  return id, "ok", encoded
end

-- Module state: one work context, created on first use, and the callers waiting for a result.
local work_context
local waiting = {} -- id -> state of the suspended call
local last_id = 0
local bytecode = core.weak_table("k") -- function -> its bytecode

local function on_done(id, status, data, traceback)
  local state = waiting[id]
  if state == nil then return end -- a cancelled caller: the late result is discarded
  waiting[id] = nil
  state.status, state.data, state.traceback = status, data, traceback
  state.wake()
end

--- Returns the bytecode of `fn`, or raises `ArgumentError` when it cannot run on a pool thread.
---@param fn any
---@return string
local function dump(fn)
  local code = bytecode[fn]
  if code then return code end
  if type(fn) ~= "function" then
    error(core.ArgumentError(("reactor.offload: expects a function, got %s"):format(type(fn))), 3)
  end
  if debug.getinfo(fn, "S").what == "C" then
    error(core.ArgumentError("reactor.offload: expects a Lua function, got a C function"), 3)
  end
  local index = 1
  while true do
    local name = debug.getupvalue(fn, index)
    if name == nil then break end
    if name ~= "_ENV" then
      error(core.ArgumentError(("reactor.offload: the function captures the local variable %s, but only "
        .. "self-contained functions (no upvalue other than _ENV) can run on the thread pool; pass the value "
        .. "as an argument"):format(name == "" and "(unnamed)" or name)), 3)
    end
    index = index + 1
  end
  code = string.dump(fn)
  bytecode[fn] = code
  return code
end

---@class hecate.reactor
local M = { OffloadError = OffloadError }

--- Runs `fn(...)` on libuv's thread pool, in the separate Lua state of a pool thread, and returns
--- its results. Use it for CPU-bound work of a millisecond or more (hashing, compression, parsing a
--- large document), which would otherwise stall every computation of the reactor.
---
--- `fn` must be self-contained: a Lua function with no upvalue other than `_ENV`. On the pool
--- thread it sees the standard libraries and `require` (with the paths of `LUA_PATH` and
--- `LUA_CPATH`), nothing of the reactor thread, and it must not suspend. Arguments and results
--- are copied: `nil`, booleans, numbers, strings and plain tables of them (no metatable, no
--- cycle, at most 100 levels).
---
--- A running function cannot be interrupted: a cancelled caller is released at once and the
--- late result is discarded. The pool (4 threads unless `UV_THREADPOOL_SIZE` says otherwise) is
--- shared with the file system and name resolution.
---
--- Raises `hecate.reactor.OffloadError` (`context.traceback`: the traceback on the pool thread)
--- when `fn` raises or returns a value that cannot be copied, and `hecate.core.ArgumentError` for
--- a function or an argument that cannot be sent.
---@async
---@param fn fun(...): ...  a self-contained Lua function
---@param ... any  its arguments
---@return any ...  its results
function M.offload(fn, ...)
  local code = dump(fn)
  local ok, payload = pcall(transfer.codec.encode, "argument", select("#", ...), { ... })
  if not ok then error(core.ArgumentError("reactor.offload: " .. tostring(payload)), 2) end
  uv_call.begin("reactor.offload")
  if work_context == nil then work_context = uv.new_work(work, on_done) end
  last_id = last_id + 1
  local id, state = last_id, {}
  local suspended, failure = pcall(context.suspend, function(wake)
    state.wake = wake
    waiting[id] = state
    local called, queued, queue_error = pcall(uv.queue_work, work_context, id, transfer.code, code, payload)
    if not called or not queued then
      waiting[id] = nil
      state.status, state.data = "refused", tostring(called and queue_error or queued)
      wake()
    end
  end)
  if not suspended then
    waiting[id] = nil
    error(failure, 0)
  end
  if state.status == "ok" then
    local n, values = transfer.codec.decode(state.data)
    return table.unpack(values, 1, n)
  end
  if state.status == "refused" then
    error(core.Error("reactor.offload: libuv refused the work: " .. state.data), 0)
  end
  error(OffloadError({
    message = "reactor.offload: " .. state.data,
    context = { traceback = state.traceback },
  }), 0)
end

return M
