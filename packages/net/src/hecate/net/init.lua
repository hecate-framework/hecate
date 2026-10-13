-- hecate.net: streams over the reactor (concurrency.md; ADR 0002, ADR 0003). Step 1 of the
-- roadmap item: the buffered reader and writer; step 3: TCP streams and listeners. UDP and TLS follow.
global <const> require

local tcp = require("hecate.net.tcp")

--- Streams over the reactor: the `Stream` interface, TCP streams and listeners, and buffered
--- readers and writers.
---@class hecate.net
---@field BufferedReader hecate.net.BufferedReader
---@field BufferedWriter hecate.net.BufferedWriter
---@field Stream table  interface a transport implements
---@field EndOfStreamError hecate.core.NetworkError
---@field TcpStream hecate.net.TcpStream
---@field TcpListener hecate.net.TcpListener
local net = {
  BufferedReader = require("hecate.net.buffered_reader"),
  BufferedWriter = require("hecate.net.buffered_writer"),
  Stream = require("hecate.net.stream"),
  EndOfStreamError = require("hecate.net.errors").EndOfStreamError,
  ---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
  TcpStream = require("hecate.net.tcp_stream"),
  ---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
  TcpListener = require("hecate.net.tcp_listener"),
}

-- Assigned, not in the constructor, so that the LuaLS export lists the documented functions of
-- tcp.lua (coding-standards.md, "Annotations for the reference").
net.connect = tcp.connect
net.listen = tcp.listen

return net
