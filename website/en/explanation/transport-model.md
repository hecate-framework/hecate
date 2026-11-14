---
description: How hecate moves bytes over the network: streams, suspension instead of callbacks, back-pressure, half-close, buffering, cancellation rules and why close never suspends.
hecate: "0.x"
lua: "5.5"
order: 1
---

# The transport model

This page explains how `hecate.reactor` and `hecate.net` move bytes between processes, and why the API has the shape
it has. It is written for hecate 0.x and Lua 5.5. For recipes, read
[Connect and serve over TCP](../how-to/connect-and-serve-over-tcp.md).

## Two layers

Two packages share the work. `hecate.reactor` wraps the network handles of libuv once: TCP, UDP, pipes and name
resolution. `hecate.net` builds on it. It adds name resolution before connecting, the buffered reader and writer,
and TLS.

`net` never talks to libuv itself. Everything that waits goes through the
[reactor](../reference/glossary.md#concurrency), the event demultiplexer that schedules the coroutines of a process.
That is why the rules below hold for every transport.

## Streams

A [stream](../reference/glossary.md#concurrency) is an ordered sequence of bytes that is read, written and closed in
order. A TCP connection, a Unix socket, a named pipe and a TLS session are all streams. The `Stream` interface asks
for three operations:

- `read(max)` returns the bytes one receive delivered, at most `max` of them. It never returns an empty string. It
  returns `nil` at the end of the stream.
- `write(data)` accepts all of `data`, or raises. It never reports a partial write.
- `close()` is idempotent and never suspends, except `BufferedWriter:close`, which flushes first (see below).

A stream may also offer `shutdown()` for a half-close, and `is_closed()`. Streams are `<close>`-able.

Streams compose. The buffered reader and writer work over any stream. A TLS stream is a stream over another stream,
which it owns.

A UDP socket is not a stream. Each call moves one datagram, and boundaries matter.

## Suspension instead of callbacks

No callback is ever exposed to your code. A call such as `read` suspends the running
[coroutine](../reference/glossary.md#concurrency), the Lua unit of execution. The reactor runs other coroutines
meanwhile, and resumes this one when the operating system has an answer. Your action therefore reads as sequential
code:

```lua
local line = reader:read_line()
writer:write(answer(line))
writer:flush()
```

The price is that you must call such functions from a managed coroutine. Outside one, they raise
`NonYieldableContextError`. So do they inside a function that Lua cannot yield across, such as the comparator of
`table.sort`.

## Back-pressure

A producer must not outrun its consumer without bound. In hecate, the producer *suspends* instead of piling data up
in memory. This is [back-pressure](../reference/glossary.md#concurrency).

It works on both sides of a connection:

- `write` suspends until the operating system has accepted the data. When the peer reads slowly, its receive window
  fills and your writes wait.
- On the reading side, a TCP stream reads ahead up to 64 KiB, then stops reading until your code catches up. The
  peer's window then closes, and its writes wait in turn. A message pipe does not read ahead.
- The buffered reader bounds a line or record (65536 bytes by default), so a peer cannot make you buffer an
  unbounded line. `read_exact` takes a `limit` for the same reason.

## Half-close

A connection has two directions. `shutdown()` ends the outgoing one and leaves the incoming one open: this is a
[half-close](../reference/glossary.md#concurrency). The peer sees the end of the stream, answers, and closes.

In the example, the client sends its request, then calls `shutdown`. The server reads until the end of the stream,
then answers:

<!-- example: packages/net/examples/hecate.net.TcpStream.shutdown.lua -->
```lua
-- A half-close. The client sends its request, then calls `shutdown` to say that
-- nothing more follows; it can still read. The server reads until the end of
-- the stream, then answers.
local reactor = require("hecate.reactor")
local net = require("hecate.net")

reactor.run(function()
  local listener <close> = net.listen("127.0.0.1", 0)
  reactor.fork(function()
    local peer <close> = listener:accept()
    local reader, writer = peer:reader(), peer:writer()
    local size = 0
    while true do
      local chunk = reader:read_some(4096)
      if chunk == nil then break end -- the client's half-close
      size = size + #chunk
    end
    writer:write(("received %d bytes\n"):format(size))
    writer:flush()
  end)
  local client <close> = net.connect("127.0.0.1", listener:local_address().port)
  client:write(("x"):rep(1000))
  client:shutdown() -- no more data from this side; the stream stays readable
  print(client:reader():read_line())
end)
-- Prints: received 1000 bytes
```

Protocols that mark the end of a request this way rely on it. For TLS, `shutdown()` also sends `close_notify`.

## Buffering

The buffered reader keeps bytes that arrived but were not consumed. `read_until` searches each chunk once, so the
cost is linear in the length of the record, however it was chunked.

The buffered writer collects small writes. It sends them when `flush` is called, or when the buffer reaches its
capacity (16384 bytes by default, one TLS record). A payload at least as large as the capacity, written while
nothing is buffered, goes to the stream directly, without a copy.

Neither the reader nor the writer owns its stream. Closing a writer flushes what it still holds, even when the
surrounding scope is cancelled. The flush is bounded by `close_timeout`, five seconds by default.

A writer whose flush failed or was cancelled is *poisoned*: it cannot know how much was sent. Until it is closed,
every later `write` or `flush` raises a `NetworkError` whose `cause` is the original failure. Closing a poisoned
writer closes it without raising, because its failure was reported already.

## Cancellation rules

Any operation can be [cancelled](../reference/glossary.md#concurrency), by a deadline or by its scope. libuv can
withdraw a pending read or accept. It cannot withdraw a write, a connect or a shutdown that was handed to the
operating system. The rules follow from that:

- A cancelled `read`, `accept` or `receive_from` leaves the object usable and loses nothing.
- A cancelled `write`, `send_to`, `shutdown` or `connect` closes the object, because how much was sent is unknown.

In the example, a deadline cancels a read on a silent server. The stream and the reader stay intact, and the next
read gets the late answer:

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

No operation takes a timeout argument: you wrap it in `reactor.deadline`. The table of every operation is in
[Deadlines and cancellation on streams](../how-to/deadlines-and-cancellation.md).

## One reader at a time

One coroutine reads, accepts or receives at a time on an object. A second concurrent call raises `core.StateError`
instead of waiting. Two readers would split the bytes of one stream between them, so the data each sees would
depend on scheduling.

Writes behave differently. Writes from several coroutines are queued in call order. A buffered reader or writer also
queues a second concurrent call instead of raising.

Create one buffered reader per stream. The library does not enforce it: a second reader over the same stream is not
refused, and the two readers split its bytes.

## Why `close` never suspends

`close` is the last thing that runs when a `<close>` block ends, and that includes the end caused by a cancellation.
A cancelled coroutine must be able to release its resources without waiting for the network. So `close` returns at
once, and wakes every coroutine waiting on the object with `ECANCELED`.

The consequence is that the `close` of a stream cannot do work that needs the network: it cannot send a TLS
`close_notify`. You do that explicitly, before the block ends: `stream:shutdown()`.

A buffered writer is the one exception. Its `close` flushes the buffered bytes under `reactor.shield`, so the flush
survives a cancellation. The `close_timeout` option (5 seconds by default) keeps a stuck peer from blocking it.

## Errors

A failure of the transport raises `reactor.TransportError`, a `NetworkError`. Its context tells what failed:

- `context.errno` is the libuv name, such as `ECONNREFUSED`, `EPIPE` or `EBADF` (a closed object);
- `context.operation` names the operation.

`IoError` is kept for the file system and processes. A failed TLS handshake or verification raises `TlsError`, also
a `NetworkError`.

## See also

- [Deadlines and cancellation on streams](../how-to/deadlines-and-cancellation.md)
- [TLS trust and security defaults](tls-trust-and-security.md)
- Reference: [`hecate.net`](../reference/net/index.md), [`Stream`](../reference/net/Stream.md),
  [`hecate.reactor`](../reference/reactor/index.md)
