-- hecate.net: streams over the reactor (concurrency.md; ADR 0002, ADR 0003). Step 1 of the
-- roadmap item: the buffered reader and writer. TCP, UDP, DNS and TLS follow.
global <const> require

---@class hecate.net
---@field BufferedReader hecate.net.BufferedReader
---@field BufferedWriter hecate.net.BufferedWriter
---@field Stream table  interface a transport implements
---@field EndOfStreamError hecate.core.NetworkError
local net = {
  BufferedReader = require("hecate.net.buffered_reader"),
  BufferedWriter = require("hecate.net.buffered_writer"),
  Stream = require("hecate.net.stream"),
  EndOfStreamError = require("hecate.net.errors").EndOfStreamError,
}

return net
