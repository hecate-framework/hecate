-- `reactor.offload`: runs a self-contained Lua function on libuv's thread pool, in the Lua state
-- of a pool thread, and suspends the caller until it returns (concurrency.md, "Offload"; OQ-27,
-- OQ-119). The basis is luv's `new_work`/`queue_work`, used unmodified (OQ-1). luv passes at most
-- nine scalar values each way and swallows an error of the work function (the caller would then
-- wait forever), so arguments and results travel as one string encoded by `internal/transfer`,
-- and `work` below runs every step of its own under `pcall` and always answers with the id.
global <const> type, error, require, pcall, xpcall, tostring, debug, table, string, select, load, setmetatable

local core = require("hecate.core")
local uv = require("luv")
local uv_call = require("hecate.reactor.internal.uv_call")
local context = require("hecate.reactor.internal.context")
local transfer = require("hecate.reactor.internal.transfer")

--- Raised by `reactor.offload` when the offloaded function raises, returns a value that cannot
--- cross between Lua states, or cannot be run on the pool thread.
---@class hecate.reactor.OffloadError : hecate.core.Error
---@field context { reason: "raised"|"result"|"worker", traceback?: string, code?: string }
local OffloadError = core.error_class("OffloadError", "hecate.reactor.OffloadError", core.Error)

--- Runs on a pool thread. Sent as bytecode by luv, so it has no upvalue but `_ENV` (the global
--- table of the pool thread's state); every value it needs arrives as an argument. The offloaded
--- function gets a fresh environment whose reads fall through to the global table, so an
--- assignment to a global stays in that call and cannot break the next one on this thread.
--- Returns `id, "ok", encoded results` or `id, reason, message, traceback?, code?`.
---@param id integer
---@param codec_code string  bytecode of `transfer.factory`
---@param fn_code string  bytecode of the offloaded function
---@param payload string  the encoded arguments
---@return integer id
---@return string status
---@return string data
---@return string? traceback
---@return string? code
local function work(id, codec_code, fn_code, payload)
  local globals = _ENV
  local function run()
    local key = "hecate.reactor.offload.codec" -- a literal: `work` may not capture an upvalue
    local registry = debug.getregistry()
    local cached = registry[key]
    if cached == nil or cached.code ~= codec_code then
      local factory = load(codec_code, "=hecate.reactor.offload codec", "b") --[[@as function]]
      cached = { code = codec_code, codec = factory() }
      registry[key] = cached
    end
    local codec = cached.codec
    local environment = setmetatable({}, { __index = globals })
    local fn, load_error = load(fn_code, nil, "b", environment)
    if fn == nil then return "worker", "cannot load the function: " .. tostring(load_error) end
    local n, args = codec.decode(payload)
    local function handler(err)
      local message, code
      if type(err) == "table" then
        local ok, field = pcall(function() return err.message end)
        if ok and type(field) == "string" then message = field end
        local has_code, value = pcall(function() return err.code end)
        if has_code and type(value) == "string" then code = value end
      end
      if message == nil then
        local ok, text = pcall(tostring, err)
        message = ok and type(text) == "string" and text or "(an error that cannot be converted to a string)"
      end
      return { message = message, traceback = debug.traceback(message, 2), code = code }
    end
    local results = table.pack(xpcall(fn, handler, table.unpack(args, 1, n)))
    if not results[1] then return "raised", results[2].message, results[2].traceback, results[2].code end
    local encoded_ok, encoded = pcall(codec.encode, "result", results.n - 1, results, 2)
    if not encoded_ok then return "result", tostring(encoded) end
    return "ok", encoded
  end
  local ok, status, data, traceback, code = pcall(run)
  if not ok then
    local text_ok, text = pcall(tostring, status)
    return id, "worker", "the pool thread failed: " .. (text_ok and text or "unknown error")
  end
  return id, status, data, traceback, code
end

-- Module state: one work context, created on first use, and the callers waiting for a result.
local work_context
local waiting = {} -- id -> state of the suspended call
local last_id = 0
local bytecode = core.weak_table("k") -- function -> its bytecode

local function on_done(id, status, data, traceback, code)
  context.offloads_in_flight = (context.offloads_in_flight or 1) - 1
  local state = waiting[id]
  if state == nil then return end -- a cancelled caller: the late result is discarded
  waiting[id] = nil
  state.status, state.data, state.traceback, state.code = status, data, traceback, code
  state.wake()
end

--- Returns the bytecode of `fn`, or raises `ArgumentError` when it cannot run on a pool thread.
---@param fn any
---@return string
local function dump(fn)
  if type(fn) ~= "function" then
    error(core.ArgumentError(("reactor.offload: expects a function, got %s"):format(type(fn))), 3)
  end
  local code = bytecode[fn]
  if code then return code end
  if debug.getinfo(fn, "S").what == "C" then
    error(core.ArgumentError("reactor.offload: expects a Lua function, got a C function"), 3)
  end
  local index = 1
  while true do
    local name = debug.getupvalue(fn, index)
    if name == nil then break end
    if name == "" or name == "(no name)" then
      error(core.ArgumentError("reactor.offload: the function has no debug information (stripped bytecode), so "
        .. "its upvalues cannot be checked; offload a function compiled with debug information"), 3)
    end
    if name ~= "_ENV" then
      error(core.ArgumentError(("reactor.offload: the function captures the local variable %s, but only "
        .. "self-contained functions (no upvalue other than _ENV) can run on the thread pool; pass the value "
        .. "as an argument"):format(name)), 3)
    end
    index = index + 1
  end
  code = string.dump(fn)
  bytecode[fn] = code
  return code
end

---@class hecate.reactor
local M = {}

M.OffloadError = OffloadError

--- Runs `fn(...)` on libuv's thread pool, in the separate Lua state of a pool thread, and returns
--- its results. Use it for CPU-bound work of a millisecond or more (hashing, compression, parsing a
--- large document), which would otherwise stall every computation of the reactor.
---
--- `fn` must be self-contained: a Lua function with no upvalue other than `_ENV`. On the pool
--- thread it sees the standard libraries and `require` (with the paths of `LUA_PATH` and
--- `LUA_CPATH`) through a fresh environment, nothing of the reactor thread, and it must not
--- suspend. Arguments and results are copied: `nil`, booleans, numbers, strings and plain tables of
--- them (no metatable, no cycle, at most 100 levels).
---
--- A running function cannot be interrupted: a cancelled caller is released at once and the late
--- result is discarded, but `reactor.run` returns only once every offloaded function has returned.
--- The pool (4 threads unless `UV_THREADPOOL_SIZE` says otherwise) is shared with the file system
--- and name resolution.
---
--- Raises `hecate.reactor.OffloadError` when `fn` raises (`context.reason` `"raised"`,
--- `context.traceback` from the pool thread, `context.code` the `code` of a framework error),
--- returns a value that cannot be copied (`"result"`) or cannot run on the pool thread
--- (`"worker"`); `hecate.core.ArgumentError` for a function or an argument that cannot be sent;
--- `hecate.reactor.IoError` when libuv refuses the work.
---@async
---@param fn fun(...): ...  a self-contained Lua function
---@param ... any  its arguments
---@return any ...  its results
function M.offload(fn, ...)
  local code = dump(fn)
  local ok, payload = pcall(transfer.codec.encode, "argument", select("#", ...), { ... })
  if not ok then error(core.ArgumentError("reactor.offload: " .. tostring(payload)), 2) end
  uv_call.begin("reactor.offload")
  if work_context == nil then
    local created, result = pcall(uv.new_work, work, on_done)
    if not created or not result then uv_call.fail("reactor.offload", "new_work", tostring(result)) end
    work_context = result
  end
  last_id = last_id + 1
  local id, state = last_id, {}
  local suspended, failure = pcall(context.suspend, function(wake)
    state.wake = wake
    waiting[id] = state
    local called, queued, queue_error = pcall(uv.queue_work, work_context, id, transfer.code, code, payload)
    if called and queued then
      context.offloads_in_flight = (context.offloads_in_flight or 0) + 1
    else
      waiting[id] = nil
      state.status, state.data = "refused", tostring(called and queue_error or queued)
      wake()
    end
  end)
  if not suspended then
    waiting[id] = nil
    error(failure, 0)
  end
  local status = state.status
  if status == "ok" then
    local n, values = transfer.codec.decode(state.data)
    return table.unpack(values, 1, n)
  end
  if status == "refused" then uv_call.fail("reactor.offload", "queue_work", state.data) end
  error(OffloadError({
    message = "reactor.offload: " .. state.data,
    context = { reason = status, traceback = state.traceback, code = state.code },
  }), 0)
end

return M
