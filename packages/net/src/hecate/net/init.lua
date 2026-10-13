-- hecate.net: streams over the reactor (concurrency.md; ADR 0002, ADR 0003). Step 1 of the
-- roadmap item: the buffered reader and writer; step 3: TCP streams and listeners. UDP and TLS follow.
global <const> require

local tcp = require("hecate.net.tcp")

---@class hecate.net
---@field BufferedReader hecate.net.BufferedReader
---@field BufferedWriter hecate.net.BufferedWriter
---@field Stream table  interface a transport implements
---@field EndOfStreamError hecate.core.NetworkError
---@field TcpStream hecate.net.TcpStream
---@field TcpListener hecate.net.TcpListener
---@field connect fun(host: string, port: integer, options?: table): hecate.net.TcpStream
---@field listen fun(host: string, port: integer, options?: table): hecate.net.TcpListener
local net = {
  BufferedReader = require("hecate.net.buffered_reader"),
  BufferedWriter = require("hecate.net.buffered_writer"),
  Stream = require("hecate.net.stream"),
  EndOfStreamError = require("hecate.net.errors").EndOfStreamError,
  ---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
  TcpStream = require("hecate.net.tcp_stream"),
  ---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
  TcpListener = require("hecate.net.tcp_listener"),
  connect = tcp.connect,
  listen = tcp.listen,
}

return net
