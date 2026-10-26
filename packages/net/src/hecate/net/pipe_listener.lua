-- PipeListener: accepts `PipeStream`s over a reactor pipe listener.
global <const> require

local core = require("hecate.core")
local PipeStream = require("hecate.net.pipe_stream")

--- A listening pipe that accepts `PipeStream`s.
---@class hecate.net.PipeListener
---@overload fun(inner: hecate.reactor.PipeListener): hecate.net.PipeListener
local PipeListener = core.class("PipeListener")

--- Wraps a reactor listener, which this listener owns. Prefer `net.listen_pipe`.
---@param inner hecate.reactor.PipeListener
---@private
function PipeListener:init(inner)
  self._inner = inner
  ---@diagnostic disable-next-line: inject-field  -- the reactor listener names this class in its messages
  inner._label = "net.PipeListener"
end

--- Suspends until a connection arrives. Cancelling keeps the listener open and the queued
--- connections.
---@async
---@return hecate.net.PipeStream
function PipeListener:accept()
  ---@diagnostic disable-next-line: param-type-mismatch  -- the reactor listener wraps its clients in PipeStreams
  return PipeStream(self._inner:accept())
end

--- Stops listening. Idempotent, never suspends. Accepted streams are unaffected.
function PipeListener:close() self._inner:close() end

--- Closes at the end of a `<close>` scope.
function PipeListener:__close() self._inner:close() end

---@return boolean
function PipeListener:is_closed() return self._inner:is_closed() end

--- Path the listener is bound to.
---@return string
function PipeListener:path() return self._inner:path() end

return core.finalise(PipeListener)
