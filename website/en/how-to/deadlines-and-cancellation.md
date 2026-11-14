---
description: Bound connects, reads, writes and accepts with reactor.deadline, and know what each cancelled operation leaves behind.
hecate: "0.x"
lua: "5.5"
order: 3
---

# Deadlines and cancellation on streams

This guide shows how to bound a network operation in time, and what state a stream is in after the operation was
cancelled. It is written for hecate 0.x and Lua 5.5. It assumes you know
[how to connect and serve over TCP](connect-and-serve-over-tcp.md).

## Bound an operation with `reactor.deadline`

The connects, reads, writes and accepts of `hecate.net` take no timeout argument. You bound any of them in the same
way: wrap the call in `reactor.deadline(seconds, fn, ...)`.

```lua
local stream <close> = reactor.deadline(5, net.connect, "example.org", 80)
```

`reactor.deadline` runs `fn` with the arguments that follow it and returns its results. When the
[deadline](../reference/glossary.md#concurrency), the bound on the call, passes first, it
[cancels](../reference/glossary.md#concurrency) `fn` and raises `DeadlineExceededError`. Cancellation is a
cooperative request to stop: the cancelled [coroutine](../reference/glossary.md#concurrency) receives it at its next
suspension point, that is, at its next call that waits.

A cancellation can also come from elsewhere, for example from an enclosing `reactor.scope`. That one raises
`CancellationError` instead. The two classes are siblings under `Error`: a `DeadlineExceededError` is not a
`CancellationError`. The state a [stream](../reference/glossary.md#concurrency) is left in is the same for both.

Two options carry a timeout of their own. `handshake_timeout` bounds a TLS handshake, and `close_timeout` bounds the
flush that `BufferedWriter:close` performs. Both are described below.

## Bound a connect

The deadline around `net.connect` also bounds name resolution, because `net.connect` resolves the host inside the
call. The snippet above therefore gives the whole connection 5 seconds, resolution included.

A cancellation stops `connect` at once. It cancels every attempt in flight and does not try the next address. The
half-open connections are closed, so nothing leaks.

`net.connect_tls` has two bounds:

- The `reactor.deadline` you wrap around it bounds the whole call: resolution, TCP connect and TLS handshake.
- The option `handshake_timeout` (10 seconds by default) bounds the TLS handshake alone.

```lua
local stream <close> = reactor.deadline(5, net.connect_tls, host, 443, { handshake_timeout = 5 })
```

## Bound a read

A read that is cancelled loses nothing. The stream and its reader stay usable, and the bytes that had already arrived
stay in the reader. You can read again later.

In the example below, the server stays silent past the deadline. The first read is cancelled; the second one gets the
answer.

<!-- example: packages/net/examples/hecate.net.TcpStream.read.lua -->
```lua
-- A deadline around a read. The server stays silent, so the read is cancelled
-- when the deadline passes. Nothing is lost: the stream and the reader are
-- intact, and the next read gets the answer when it comes. (A write cancelled
-- by a deadline would have closed the stream.)
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

This is the idiom for an idle timeout. Run the read inside a deadline. On `DeadlineExceededError`, decide whether to
wait again or to close the stream.

## Bound an accept

```lua
local ok, stream = pcall(reactor.deadline, 30, function() return listener:accept() end)
```

A cancelled `accept` keeps the listener open, with the connections already queued in it. It works the same for a pipe
listener.

This is how a server stops its accept loop: it cancels the coroutine that runs the loop, then closes the listener.

## What a cancelled operation leaves behind

A read or an accept can be withdrawn: nothing was taken from the peer yet. A write cannot. Once the operating system
has taken some of the bytes, nobody knows how many were sent. Such an operation closes its object instead of leaving
it in an unknown state.

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
| TLS handshake that outlasts `handshake_timeout` | The stream is closed. |

## Know the poisoned writer

A `BufferedWriter` that failed to flush, or whose flush was cancelled, cannot say how much of its buffer left. Sending
the rest would be wrong: the peer would receive bytes after a gap.

The writer is therefore *poisoned*. Every later call raises a `NetworkError` whose `cause` is the failure that
poisoned it. For a cancelled flush, that cause is the `CancellationError` the write received, even when a deadline
cancelled it.

```lua
local ok, err = pcall(reactor.deadline, 2, function() writer:flush() end)
if not ok then
  -- The stream is closed and the writer is poisoned: open a new connection.
end
```

Reading from the same stream is not an option either: the cancelled write closed it. Treat a cancelled write as the
end of the connection.

## Let `close` flush a writer

`BufferedWriter:close` flushes the bytes the writer still holds. It runs that flush under `reactor.shield`, so the
flush completes inside a `<close>` block even while the coroutine is being cancelled.

The writer option `close_timeout` (5 seconds by default) bounds that flush. If the peer is stuck, `close` raises
`DeadlineExceededError`. The writer is closed anyway, and the unsent bytes are dropped.

`close` does not shut the stream down. To end a conversation cleanly, call `shutdown` too. See
[The transport model](../explanation/transport-model.md).

## Run cleanup while the scope is cancelled

Once a [scope](../reference/glossary.md#concurrency), the region that owns a group of computations, is cancelled,
every suspension point inside it raises again. A cleanup step that must wait, such as flushing a buffer or sending a
closing message, would therefore fail at once.

Run such a step with `reactor.shield(limit, fn)`. The shield keeps the cancellation of the enclosing scopes out of its
body. It has a deadline of its own, so that a stuck peer cannot block shutdown.

```lua
local ok = pcall(reactor.shield, 5, function()
  writer:flush()
  stream:shutdown()
end)
-- A deadline of 5 seconds bounds the cleanup.
-- ok is false if it expired or failed.
```

The cancellation that arrived meanwhile is not lost. It is raised again at the first suspension point after the
shield.

## See also

- [Connect and serve over TCP](connect-and-serve-over-tcp.md)
- [Concurrency](concurrency.md): `reactor.deadline`, scopes and `select`
- Reference: [`reactor.deadline`](../reference/reactor/functions/deadline.md),
  [`reactor.shield`](../reference/reactor/functions/shield.md),
  [`BufferedWriter`](../reference/net/BufferedWriter.md)
