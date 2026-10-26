---
description: Exchange UDP datagrams, listen on Unix sockets and Windows named pipes, and resolve host names with hecate.net.
hecate: "0.x"
lua: "5.5"
order: 4
---

# UDP, Unix sockets, named pipes and DNS

This guide covers the transports of `hecate.net` other than TCP: datagrams, local sockets and
name resolution. It is written for hecate 0.x and Lua 5.5. All calls suspend the running
[coroutine](../reference/glossary.md#concurrency), so run them inside `reactor.run`.

## Exchange datagrams

`net.bind_udp(host, port, options?)` binds a `UdpSocket` to the first address `host` resolves
to. Port `0` picks a free port. The only option is `family`.

Each `send_to` sends one datagram, and each `receive_from` returns one datagram together with
the address of its sender, as `{ ip, port, family }`. The payload may be empty. A datagram is
never split or merged, unlike the bytes of a stream.

<!-- example: packages/net/examples/hecate.net.bind_udp.lua -->
```lua
-- A datagram exchange over the loopback interface: two sockets on free ports,
-- one datagram each way. `send_to` takes a numeric address (resolve a name
-- first with `net.resolve`), and each `receive_from` returns exactly one
-- datagram with the sender's address.
local reactor = require("hecate.reactor")
local net = require("hecate.net")

reactor.run(function()
  local server <close> = net.bind_udp("127.0.0.1", 0)
  local client <close> = net.bind_udp("127.0.0.1", 0)
  reactor.fork(function()
    local payload, from = server:receive_from()
    server:send_to(from.ip, from.port, payload:upper())
  end)
  client:send_to("127.0.0.1", server:local_address().port, "ping")
  local reply = client:receive_from()
  print(reply)
end)
-- Prints: PING
```

Things to know:

- `send_to(host, port, data)` puts the destination first, like `net.connect`.
- A UDP socket serves one `receive_from` at a time. A second concurrent call raises an error.
- A `receive_from` that is cancelled loses no datagram. A `send_to` that is cancelled closes
  the socket. See [Deadlines and cancellation on streams](deadlines-and-cancellation.md).
- Datagram truncation and loss are neither specified nor tested yet: size your datagrams below
  the path MTU and do not assume delivery.
- `::` is dual-stack on Linux and macOS, and IPv6 only on Windows by default. There is no option
  to change it.

## Resolve a name before you send

`send_to` accepts a numeric address only. A host name raises `ArgumentError` that points to
`net.resolve`. A datagram has no connection, so there is no second address to retry on.

`net.resolve(host, options?)` returns the numeric addresses in the resolver's order, as a list of
`{ ip, family }`. `family` (`"inet"` or `"inet6"`) keeps one kind.

<!-- example: packages/net/examples/hecate.net.resolve.lua -->
```lua
-- Name resolution. `resolve` returns the numeric addresses of a host in the
-- resolver's order; `family` keeps one kind. `UdpSocket:send_to` takes a
-- numeric address only, so a datagram to a name goes through `resolve` first.
local reactor = require("hecate.reactor")
local net = require("hecate.net")

reactor.run(function()
  local addresses = net.resolve("localhost", { family = "inet" })
  local socket <close> = net.bind_udp("127.0.0.1", 0)
  socket:send_to(addresses[1].ip, socket:local_address().port, "hello")
  local payload = socket:receive_from()
  print(addresses[1].ip .. " " .. payload)
end)
-- Prints: 127.0.0.1 hello
```

When a name does not resolve, `resolve` raises a `reactor.TransportError`. Its message and
`context.host` carry the name, and `context.errno` is the resolver's code, for example
`EAI_NONAME`. A cancelled resolution returns at once and its late result is discarded.

Resolution runs on the libuv thread pool (four threads by default) and is not cached. Bound it with
`reactor.deadline` like any other call.

## Listen on a Unix socket or a named pipe

`net.listen_pipe(path, options?)` listens on a Unix-domain socket. On Windows the same call
listens on a named pipe, whose path has the form `\\.\pipe\name`. The streams are `PipeStream`
objects with the same API as `TcpStream`: `reader`, `writer`, `shutdown`, `close` and so on, plus
`path()`.

<!-- example: packages/net/examples/hecate.net.listen_pipe.lua -->
```lua
-- A Unix-domain socket (a named pipe on Windows) in place of TCP: the stream
-- and the buffered API are the same. The path must not exist; `mode` says who
-- may connect (default: the owner).
local reactor = require("hecate.reactor")
local net = require("hecate.net")

local WINDOWS = package.config:sub(1, 1) == "\\"
local name = ("hecate-example-%x-%d"):format(os.time(), math.random(0, 1 << 30))
local path = WINDOWS and ("\\\\.\\pipe\\" .. name) or ((os.getenv("TMPDIR") or "/tmp") .. "/" .. name .. ".sock")

reactor.run(function()
  local listener <close> = net.listen_pipe(path, { mode = "owner" })
  reactor.fork(function()
    local peer <close> = listener:accept()
    local reader, writer = peer:reader(), peer:writer()
    writer:write(reader:read_line():upper() .. "\n")
    writer:flush()
  end)
  local client <close> = net.connect_pipe(path)
  local reader, writer = client:reader(), client:writer()
  writer:write("hello\n")
  writer:flush()
  print(reader:read_line())
end)
-- Prints: HELLO
```

`listen_pipe` does not suspend. `net.connect_pipe(path)` suspends and returns the `PipeStream`.

### Options and limits

- `backlog` is a positive integer, 128 by default. It is ignored on Windows.
- `mode` says who may connect: `"owner"` (the default), `"readable"`, `"writable"` or
  `"readwrite"`. It has no effect on Windows. On Unix the socket is made owner-only right after
  the bind. For a very short moment it has the permissions of the umask.
- The path must not exist. Binding an existing path fails with `EADDRINUSE`. The listener
  removes its socket file when it closes. After a crash a stale file stays: remove it before you
  listen again.
- A Windows pipe name is at most 256 characters. A Unix socket path is at most 107 bytes (103
  on macOS), the terminating NUL excluded. A longer path raises `ArgumentError`.

### Differences on Windows

| | Unix | Windows |
|---|---|---|
| Path | a file path | `\\.\pipe\name` |
| `mode` | applied | no effect |
| `backlog` | applied | ignored |
| Stale path after a crash | the file stays | the pipe vanishes with the process |

## See also

- [Connect and serve over TCP](connect-and-serve-over-tcp.md)
- Reference: [`net.bind_udp`](../reference/net/functions/bind_udp.md), [`UdpSocket`](../reference/net/UdpSocket.md),
  [`net.resolve`](../reference/net/functions/resolve.md),
  [`net.listen_pipe`](../reference/net/functions/listen_pipe.md),
  [`net.connect_pipe`](../reference/net/functions/connect_pipe.md)
