---
description: Connect to a TCP server, accept connections and read and write lines with hecate.net.
hecate: "0.x"
lua: "5.5"
---

# Connect and serve over TCP

This guide shows how to open a TCP connection, how to accept connections, and how to
read and write over them with `hecate.net`. It was written for hecate 0.x and Lua 5.5.

All calls that wait for the network suspend the calling
[coroutine](../reference/glossary.md#concurrency) and let the
[reactor](../reference/glossary.md#concurrency) run others. They work only inside
`reactor.run` or a coroutine started with `reactor.fork`. Outside, they raise
`NonYieldableContextError`.

## Connect to a server

`net.connect(host, port, options?)` resolves the host, tries its addresses in order and
returns a `TcpStream`. Close the stream with `<close>`.

```lua
local reactor = require("hecate.reactor")
local net = require("hecate.net")

reactor.run(function()
  local client <close> = net.connect("example.org", 80)
  local reader, writer = client:reader(), client:writer()
  writer:write("hello\n")
  writer:flush()
  print(reader:read_line())
end)
```

`reader()` and `writer()` return a buffered reader and writer over the
[stream](../reference/glossary.md#concurrency). They do not own it: closing the stream is
still your job. A writer sends nothing until it holds `capacity` bytes (8192 by default)
or you call `flush()`.

Options are checked before anything is resolved. An unknown option raises
`ArgumentError`.

| Option | Default | Meaning |
|---|---|---|
| `nodelay` | `true` | Disable Nagle's algorithm. |
| `keepalive` | `false` | Enable TCP keep-alive probes. |
| `keepalive_delay` | `60` | Seconds before the first probe. |
| `family` | any | `"inet"` or `"inet6"`. |

When no address connects, `net.connect` raises a `reactor.TransportError`. Its message
lists the addresses tried. `context.errno` holds the libuv name, for example
`ECONNREFUSED`, and `context.attempts` holds one entry per address.

## Accept connections

`net.listen(host, port, options?)` binds the first address the resolver returns. Port `0`
picks a free port. `listener:accept()` suspends until a client connects.

```lua
local listener <close> = net.listen("127.0.0.1", 0)
local port = listener:local_address().port
reactor.fork(function()
  local peer <close> = listener:accept()
  local reader, writer = peer:reader(), peer:writer()
  writer:write(reader:read_line() .. "!\n")
  writer:flush()
end)
```

The complete, tested version of this exchange is
[`hecate.net.connect.lua`](https://github.com/hecate-framework/hecate/blob/main/packages/net/examples/hecate.net.connect.lua).
It prints `hello!`.

::: tip Pass a numeric address when the address matters
`net.listen("localhost", ...)` binds whichever of `127.0.0.1` and `::1` the resolver
lists first. Pass a numeric address, or the `family` option, to choose.
:::

A real server runs the accept loop and forks one coroutine per connection, so that a slow
client never blocks the others:

```lua
reactor.scope(function(scope)
  while true do
    local peer = listener:accept()
    scope:fork(function()
      local connection <close> = peer
      -- read and write on `connection`
    end)
  end
end)
```

The scope waits for every connection coroutine and cancels the others when one fails.

## Read until a delimiter

Use the buffered reader for text protocols.

| Method | Returns |
|---|---|
| `reader:read_line()` | A line without its line feed, or `nil` at the end of the stream. |
| `reader:read_until(delimiter)` | The bytes before the delimiter, which is consumed. |
| `reader:read_exact(count, limit?)` | Exactly `count` bytes, or raises `EndOfStreamError`. |
| `reader:read_some(max)` | Buffered bytes, or the next chunk. |

A line or record longer than the reader's `limit` (65536 bytes by default) raises
`ProtocolError`. When a count comes from the peer, pass `limit` to `read_exact`, so that a
hostile peer cannot make you wait for gigabytes.

## End a conversation cleanly

`stream:shutdown()` is a [half-close](../reference/glossary.md#concurrency): you stop
sending, and the stream stays readable until the peer finishes. `stream:close()` ends both
directions and never suspends.

## Slow consumers

`write` returns once the system has accepted the bytes. When the peer reads slowly, the
call suspends: this is [back-pressure](../reference/glossary.md#concurrency), and it
bounds the memory you use.

## See also

- [Bound and cancel operations on streams](net-deadlines.md)
- [Use TLS as a client and as a server](net-tls.md)
