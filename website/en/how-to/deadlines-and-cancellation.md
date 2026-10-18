---
description: Bound connects, reads, writes and accepts with reactor.deadline, and know what each cancelled operation leaves behind.
hecate: "0.x"
lua: "5.5"
order: 3
---

# Deadlines and cancellation on streams

This guide shows how to bound a network operation in time, and what state a stream is in after
the operation was cancelled. It is written for hecate 0.x and Lua 5.5.

No operation of `hecate.net` takes a timeout argument. You bound any of them by wrapping it in
`reactor.deadline(seconds, fn, ...)`. It runs `fn`, and when the [deadline](../reference/glossary.md#concurrency)
passes it [cancels](../reference/glossary.md#concurrency) `fn` and raises `DeadlineExceededError`. A cancellation that
comes from elsewhere, for example from an enclosing `reactor.scope`, behaves the same way.

## Bound a connect

`reactor.deadline` also bounds name resolution, because `net.connect` resolves inside the call.

```lua
local stream <close> = reactor.deadline(5, net.connect, "example.org", 80)
```

A cancellation stops `connect` at once. It does not try the next address. The half-open
connection is closed, so nothing leaks. For `connect_tls`, the deadline you pass covers the TCP
connect, and `handshake_deadline` (10 seconds by default) covers the TLS handshake.

## Bound a read

A read that is cancelled loses nothing. The stream and the reader stay usable, and bytes
that had already arrived stay in the reader. You can read again later.

<!-- example: packages/net/examples/hecate.net.TcpStream.read.lua -->
```lua
-- A deadline around a read. The server stays silent, so the read is cancelled when the deadline
-- passes. Nothing is lost: the stream and the reader are intact, and the next read gets the
-- answer when it comes. (A write cancelled by a deadline would have closed the stream.)
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local net = require("hecate.net")

reactor.run(function()
  local listener <close> = net.listen("127.0.0.1", 0)
  local release = reactor.Channel()
  reactor.fork(function()
    local peer <close> = listener:accept()
    release:receive() -- stay silent until told to answer
    peer:write("late\n")
  end)
  local client <close> = net.connect("127.0.0.1", listener:local_address().port)
  local reader = client:reader()
  local ok, err = pcall(reactor.deadline, 0.05, function() return reader:read_line() end)
  local late = not ok and core.is_instance_of(err, core.DeadlineExceededError)
  release:send(true)
  print(("deadline exceeded: %s; then read: %s"):format(tostring(late), reader:read_line()))
end)
-- Prints: deadline exceeded: true; then read: late
```

This is the idiom for an idle timeout: run the read inside a deadline, and on
`DeadlineExceededError` decide whether to wait again or to close the stream.

## Bound an accept

```lua
local ok, stream = pcall(reactor.deadline, 30, function() return listener:accept() end)
```

A cancelled `accept` keeps the listener open and the connections already queued in it. It works
the same for a pipe listener. This is how a server stops its accept loop: cancel the coroutine that
runs it, then close the listener.

## What a cancelled operation leaves behind

Some operations cannot be withdrawn once started: the operating system has taken the bytes, and
nobody knows how many were sent. They close the object instead of leaving it in an unknown state.

| Operation | After a cancellation |
|---|---|
| `read`, `read_line`, `read_until`, `read_exact`, `read_some` | The stream and the reader are intact. Nothing is lost. |
| `TcpListener:accept`, `PipeListener:accept` | The listener and its queued connections are kept. |
| `UdpSocket:receive_from` | The socket is intact. No datagram is lost. |
| `write` | The stream is closed. |
| `shutdown` | The stream is closed, unless it had completed. |
| `net.connect`, `net.connect_pipe` | The half-open connection is closed. No other address is tried. |
| `UdpSocket:send_to` | The socket is closed. |
| `writer:flush`, and a `writer:write` that flushes | The writer is poisoned and the stream is closed. |
| TLS handshake that outlasts `handshake_deadline` | The stream is closed. |

## Know the poisoned writer

A `BufferedWriter` that failed to flush, or whose flush was cancelled, cannot say how much of
its buffer left. It would be wrong to send the rest. The writer is therefore *poisoned*: every
later call raises a `NetworkError` whose `cause` is the original failure.

```lua
local ok, err = pcall(reactor.deadline, 2, function() writer:flush() end)
if not ok then
  -- The stream is closed and the writer is poisoned: open a new connection.
end
```

Reading from the same stream is not an option either, since the cancelled write closed it.
Treat a cancelled write as the end of the connection.

## Do not rely on `close` to wait

`close` never suspends, so it can run inside a `<close>` block while the coroutine is being
cancelled. It does not wait for buffered data. To end a conversation cleanly, `flush` the
writer and call `shutdown` before the block ends. See
[The transport model](../explanation/transport-model.md).

## See also

- [Connect and serve over TCP](connect-and-serve-over-tcp.md)
- [`reactor.deadline`](../reference/reactor/functions/deadline.md),
  [`BufferedWriter`](../reference/net/BufferedWriter.md)
