-- hecate.net: streams over the reactor (concurrency.md; ADR 0002, ADR 0003). Step 1 of the
-- roadmap item: the buffered reader and writer; step 3: TCP streams and listeners; step 4: UDP; step 5: pipes. TLS follows.
global <const> require

local tcp = require("hecate.net.tcp")
local udp = require("hecate.net.udp")
local pipe = require("hecate.net.pipe")

--- Streams over the reactor: the `Stream` interface, TCP streams and listeners, and buffered
--- readers and writers.
---@class hecate.net
---@field BufferedReader hecate.net.BufferedReader
---@field BufferedWriter hecate.net.BufferedWriter
---@field Stream table  interface a transport implements
---@field EndOfStreamError hecate.core.NetworkError
---@field TcpStream hecate.net.TcpStream
---@field TcpListener hecate.net.TcpListener
---@field UdpSocket hecate.net.UdpSocket
---@field PipeStream hecate.net.PipeStream
---@field PipeListener hecate.net.PipeListener
local net = {
  BufferedReader = require("hecate.net.buffered_reader"),
  BufferedWriter = require("hecate.net.buffered_writer"),
  Stream = require("hecate.net.stream"),
  EndOfStreamError = require("hecate.net.errors").EndOfStreamError,
  ---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
  TcpStream = require("hecate.net.tcp_stream"),
  ---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
  TcpListener = require("hecate.net.tcp_listener"),
  ---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
  UdpSocket = require("hecate.net.udp_socket"),
  ---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
  PipeStream = require("hecate.net.pipe_stream"),
  ---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
  PipeListener = require("hecate.net.pipe_listener"),
}

-- Assigned, not in the constructor, so that the LuaLS export lists the documented functions of
-- tcp.lua (coding-standards.md, "Annotations for the reference").
net.connect = tcp.connect
net.listen = tcp.listen
net.bind_udp = udp.bind_udp
net.connect_pipe = pipe.connect_pipe
net.listen_pipe = pipe.listen_pipe

return net
