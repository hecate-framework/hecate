---
description: Exchange datagrams over UDP and connect processes of one machine through Unix-domain sockets or Windows named pipes.
hecate: "0.x"
lua: "5.5"
---

# Send datagrams and use local pipes

This guide shows how to use UDP sockets and local pipes with `hecate.net`. It was
written for hecate 0.x and Lua 5.5. Every call that waits suspends the calling
[coroutine](../reference/glossary.md#concurrency).

## Exchange datagrams over UDP

`net.bind_udp(host, port, options?)` returns a `UdpSocket` bound to the first address
the resolver lists. Port `0` picks a free port. The only option is `family`.

```lua
local server <close> = net.bind_udp("127.0.0.1", 0)
local client <close> = net.bind_udp("127.0.0.1", 0)
reactor.fork(function()
  local payload, from = server:receive_from()
  server:send_to(from.ip, from.port, payload:upper())
end)
client:send_to("127.0.0.1", server:local_address().port, "ping")
print(client:receive_from()) -- PING
```

The tested example is
[`hecate.net.bind_udp.lua`](https://github.com/hecate-framework/hecate/blob/main/packages/net/examples/hecate.net.bind_udp.lua).

- `receive_from()` returns one datagram, which can be empty, and the sender's address as
  `{ ip, port, family }`.
- `send_to(host, port, data)` sends one datagram. The destination comes first, as in
  `net.connect`.

::: warning send_to takes a numeric address only
A datagram has no connection that could retry another address. A host name raises
`ArgumentError`. Resolve it first with `net.resolve(host, { family = "inet" })`, which
returns numeric addresses in resolver order, and pick one.
:::

Cancelling `receive_from` (for example with a [deadline](net-deadlines.md)) loses no
datagram. Cancelling `send_to` closes the socket. A closed socket raises
`reactor.TransportError` with `errno` `EBADF`.

## Listen on a local pipe

A pipe connects processes of one machine. On Linux and macOS it is a Unix-domain socket
and `path` is a file path. On Windows it is a named pipe, such as `\\.\pipe\name`.

```lua
local listener <close> = net.listen_pipe("/tmp/hecate-demo.sock")
reactor.fork(function()
  local peer <close> = listener:accept()
  peer:write(peer:reader():read_line() .. "!\n")
end)

local client <close> = net.connect_pipe("/tmp/hecate-demo.sock")
client:write("hello\n")
print(client:reader():read_line()) -- hello!
```

A `PipeStream` has the same API as a `TcpStream`: `read`, `write`, `shutdown`, `close`,
`reader`, `writer`, plus `path()`. Deadlines and cancellation behave in the same way.

`net.listen_pipe` does not suspend. It raises when `path` already exists, for example a
socket file left by a crashed process: remove it first. Close the listener when you are done. Options:

| Option | Default | Meaning |
|---|---|---|
| `backlog` | `128` | Pending connections allowed. Ignored on Windows. |
| `mode` | `"owner"` | Who may connect: `"owner"`, `"readable"`, `"writable"` or `"readwrite"`. No effect on Windows. |

The default keeps the socket private to your user. Widen `mode` only when another user
must connect.

Path length is limited: 256 characters for a Windows pipe name, and the `sun_path` size of
the platform for a Unix socket (104 bytes on macOS, 108 on Linux). A longer path raises
`ArgumentError`.

## See also

- [Connect and serve over TCP](net-tcp.md)
- [Run child processes and pass connections between processes](child-processes.md)
