-- `reactor.offload`: runs a self-contained Lua function on libuv's thread pool, in the Lua state
-- of a pool thread, and suspends the caller until it returns (concurrency.md, "Offload"; OQ-27,
-- OQ-119). The basis is luv's `new_work`/`queue_work`, used unmodified (OQ-1). luv passes at most
-- nine scalar values each way and swallows an error of the work function (the caller would then
-- wait forever), so arguments and results travel as one string encoded by `internal/transfer`,
-- and `work` below runs every step of its own under `pcall` and always answers with the id.
global <const> type, error, require, pcall, xpcall, tostring, tonumber, debug, table, string, select, load, setmetatable, os, math

local core = require("hecate.core")
local uv = require("luv")
local uv_call = require("hecate.reactor.internal.uv_call")
local context = require("hecate.reactor.internal.context")
local transfer = require("hecate.reactor.internal.transfer")

--- Raised by `reactor.offload` when the offloaded function raises, returns a value that cannot
--- cross between Lua states, or cannot be run on the pool thread.
---@class hecate.reactor.OffloadError : hecate.core.Error
---@field context { reason: "raised"|"result"|"pool_thread", traceback?: string, code?: string }
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
  -- coverage: off (runs in the Lua state of a libuv pool thread, where the line hook is not installed)
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
    if fn == nil then return "pool_thread", "cannot load the function: " .. tostring(load_error) end
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
    return id, "pool_thread", "the pool thread failed: " .. (text_ok and text or "unknown error")
  end
  return id, status, data, traceback, code
  -- coverage: on
end

-- Module state. The libuv pool is one per process, so this state is too: one work context, created
-- on first use, the callers whose function is on the pool (`waiting`, by id) and the callers queued
-- here until a place on the pool is free (`queue`, first in first out). At most `limit()` functions
-- are on the pool at once (OQ-119): the others stay in `queue`, where a cancelled caller is simply
-- removed and its function never runs, and the pool keeps a thread for the file system and name
-- resolution.
local work_context
local waiting = {} -- id -> state of a call whose function is on the pool
local queue, queue_head, queue_tail = {}, 1, 0 -- states of the calls waiting for a place on the pool
local last_id = 0
local bytecode = core.weak_table("k") -- function -> its bytecode

--- The size of libuv's pool (`UV_THREADPOOL_SIZE`, default 4, at most 1024). libuv reads the value with
--- `atoi` into an unsigned integer, so a negative value gives it 1024 threads; here every value below 1
--- counts as 1: an estimate that is too small only keeps more calls in the queue, one that is too large
--- would take the threads of the file system and name resolution.
---@return integer
local function pool_size()
  local text = os.getenv("UV_THREADPOOL_SIZE")
  if text == nil then return 4 end
  local size = math.tointeger(tonumber(text:match("^%s*([+-]?%d+)")) or 0) or 0
  if size < 1 then return 1 end
  if size > 1024 then return 1024 end
  return size
end

--- How many functions may be on the pool at once: the `max_offloads` option of the running reactor,
--- otherwise the pool size minus one, at least 1.
---@return integer
local function limit()
  local running = context.reactor
  if running and running._max_offloads then return running._max_offloads end
  local size = pool_size()
  return size > 1 and size - 1 or 1
end

--- Hands the call of `state` to the pool; on refusal, wakes its caller with the reason.
local function submit(state)
  waiting[state.id] = state
  local called, queued, queue_error = pcall(uv.queue_work, work_context, state.id, transfer.code, state.code, state.payload)
  state.payload = nil
  if called and queued then
    context.offloads_in_flight = (context.offloads_in_flight or 0) + 1
    state.submitted = true
  else
    waiting[state.id] = nil
    state.status, state.data = "refused", tostring(called and queue_error or queued)
    state.wake()
  end
end

--- Submits the queued calls while the pool has room; skips the calls whose caller was cancelled.
local function dispatch()
  while queue_head <= queue_tail and (context.offloads_in_flight or 0) < limit() do
    local state = queue[queue_head]
    queue[queue_head] = nil
    queue_head = queue_head + 1
    -- A caller cancelled while queued, or closed by the teardown of a failed run (its cleanup never
    -- ran, its computation is dead): its function never runs.
    if not state.abandoned and state.computation.state ~= "dead" then
      state.queued = false
      submit(state)
    end
  end
end

local function on_done(id, status, data, traceback, code)
  context.offloads_in_flight = (context.offloads_in_flight or 1) - 1
  local state = waiting[id]
  if state ~= nil then
    waiting[id] = nil
    state.status, state.data, state.traceback, state.code = status, data, traceback, code
    state.wake()
  end -- otherwise a cancelled caller: the late result is discarded
  dispatch()
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
--- The pool-thread body, for the tests of its failure paths in this state. Not public API.
---@private
M._work = work

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
--- At most `max_offloads` functions (a `Reactor` option; default the pool size minus one, at least
--- 1) are on the pool at once; the others wait in a queue, first in first out, so a thread stays
--- free for the file system and name resolution, which share the pool (4 threads unless
--- `UV_THREADPOOL_SIZE` says otherwise). A caller cancelled while queued is removed and its function
--- never runs. A running function cannot be interrupted: its cancelled caller is released at once and
--- the late result is discarded, but `reactor.run` returns only once every running function has
--- returned.
---
--- Raises `hecate.reactor.OffloadError` when `fn` raises (`context.reason` `"raised"`,
--- `context.traceback` from the pool thread, `context.code` the `code` of a framework error),
--- returns a value that cannot be copied (`"result"`) or cannot run on the pool thread
--- (`"pool_thread"`); `hecate.core.ArgumentError` for a function or an argument that cannot be sent;
--- `hecate.reactor.IoError` when libuv refuses the work.
---@async
---@param fn fun(...): ...  a self-contained Lua function
---@param ... any  its arguments
---@return any ...  its results
function M.offload(fn, ...)
  local code = dump(fn)
  local ok, payload = pcall(transfer.codec.encode, "argument", select("#", ...), { ... })
  if not ok then error(core.ArgumentError("reactor.offload: " .. tostring(payload)), 2) end
  local computation = uv_call.begin("reactor.offload")
  if work_context == nil then
    local created, result = pcall(uv.new_work, work, on_done)
    if not created or not result then uv_call.fail("reactor.offload", "new_work", tostring(result)) end
    work_context = result
  end
  last_id = last_id + 1
  local state = { id = last_id, code = code, payload = payload, computation = computation }
  local suspended, failure = pcall(context.suspend, function(wake)
    state.wake = wake
    if (context.offloads_in_flight or 0) < limit() and queue_head > queue_tail then
      submit(state)
    else
      state.queued = true
      queue_tail = queue_tail + 1
      queue[queue_tail] = state
    end
  end)
  if not suspended then
    -- Cancelled: a queued call never reaches the pool; a submitted one runs on and its result is
    -- discarded by `on_done`.
    state.abandoned = true
    state.payload = nil -- a queued call holds its encoded arguments until `dispatch` skips it
    waiting[state.id] = nil
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
