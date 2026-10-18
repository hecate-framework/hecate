-- The contract between the buffered layer and a transport (TCP, TLS, ...). A transport is
-- any object with these three methods; `hecate.net` transports implement it.
global <const> require

local core = require("hecate.core")

--- The interface a byte stream implements: `read`, `write`, `close` and the `<close>` protocol.
---@class hecate.net.Stream
---@field read fun(self: hecate.net.Stream, max?: integer): string?  *suspends*; at most `max` bytes, nil at end of stream, never an empty string
---@field write fun(self: hecate.net.Stream, data: string)  *suspends*; returns only when every byte was accepted, or raises
---@field close fun(self: hecate.net.Stream)  idempotent, never suspends
---@field shutdown? fun(self: hecate.net.Stream)  *suspends*; ends the writing direction (half-close) when the transport has one
---@field is_closed? fun(self: hecate.net.Stream): boolean

local Stream = core.interface("Stream", { "read", "write", "close" })

return Stream
