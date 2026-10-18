---
description: Bound connections, accepts and reads with deadlines, and cancel work on streams without losing data.
hecate: "0.x"
lua: "5.5"
---

# Bound and cancel operations on streams

This guide shows how to put a limit on a network operation and what state the stream is
in afterwards. It was written for hecate 0.x and Lua 5.5.

No network call takes a timeout argument. Wrap the call in `reactor.deadline`, which
takes seconds or an absolute instant (`reactor.at`). A late call is
[cancelled](../reference/glossary.md#concurrency) and `reactor.deadline` raises
`DeadlineExceededError`. The [deadline](../reference/glossary.md#concurrency) is the bound
on the whole computation you pass in.

## Bound a connection

Resolution and connection count together.

```lua
local stream <close> = reactor.deadline(5, net.connect, "example.org", 80)
```

A deadline or cancellation stops `net.connect` at once. It does not try the next address.

## Bound a read

```lua
local reader = stream:reader()
local ok, err = pcall(reactor.deadline, 2, function() return reader:read_line() end)
if not ok and core.is_instance_of(err, core.DeadlineExceededError) then
  -- the peer was silent for two seconds
end
```

Here `core` is `require("hecate.core")`. After the deadline, the read has been withdrawn.
The stream and the reader are intact, and nothing was lost: a later `read_line` returns
the line that arrives after the expiry.

## What a cancelled operation leaves behind

| Operation | State after cancellation or deadline |
|---|---|
| `connect`, `connect_tls` | The attempt is abandoned and its handle closed. |
| `accept` | The listener and the connections it has queued are kept. |
| `read`, `read_line`, `read_exact`, `read_until` | The stream stays open and no data is lost. |
| `receive_from` (UDP) | The socket stays open and no datagram is lost. |
| `write`, `send_to` | The stream or socket is closed. |
| `flush` of a buffered writer | The writer is poisoned: later calls raise `NetworkError`. |
| TLS handshake | The stream is closed. |

A write cannot be undone because you cannot know how many bytes left. For that reason a
cancelled write closes the stream. Treat the connection as lost and reconnect.

## Limit a whole exchange

Pass a function to `reactor.deadline` to bound several operations with one deadline.

```lua
reactor.deadline(10, function()
  local stream <close> = net.connect(host, port)
  local reader, writer = stream:reader(), stream:writer()
  writer:write(request)
  writer:flush()
  return reader:read_line()
end)
```

Because `<close>` runs while the cancellation unwinds, the stream is closed on every path.

## Cancel from another coroutine

`reactor.fork` returns a [future](../reference/glossary.md#concurrency). Calling
`future:cancel()` raises `CancellationError` at the suspension point of that coroutine,
with the same effects as in the table above.

## See also

- [Connect and serve over TCP](net-tcp.md)
- [Use TLS as a client and as a server](net-tls.md)
