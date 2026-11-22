---
description: Connect to a TCP server, accept connections, read and write lines, half-close a connection and resolve host names with hecate.net.
hecate: "0.x"
lua: "5.5"
order: 1
---

# Connect and serve over TCP

This guide shows how to open a TCP connection, how to accept connections in a server, and how to read, write and close
them. It is written for hecate 0.x and Lua 5.5. For the model behind it, read
[The transport model](../explanation/transport-model.md).

Every call that waits on the network *suspends* the running [coroutine](../reference/glossary.md#concurrency): the
coroutine pauses and lets the others run until the network answers. Call these functions from a coroutine managed by
the [reactor](../reference/glossary.md#concurrency), the event loop of the process, for example inside
`reactor.run`. Outside one, they raise `NonYieldableContextError`.

## Connect

`net.connect(host, port, options?)` opens a connection and returns a `TcpStream`. The host may be a name or a numeric
address.

The example below starts a listener on a free port and connects to it. The client sends one line and reads one line
back.

<!-- example: packages/net/examples/hecate.net.connect.lua -->
```lua
-- An echo exchange over the loopback interface: a listener on a free port, a
-- client that connects to it, one line each way.
local reactor = require("hecate.reactor")
local net = require("hecate.net")

reactor.run(function()
  local listener <close> = net.listen("127.0.0.1", 0)
  reactor.fork(function()
    local peer <close> = listener:accept()
    local reader, writer = peer:reader(), peer:writer()
    writer:write(reader:read_line() .. "!\n")
    writer:flush()
  end)
  local client <close> = net.connect("127.0.0.1", listener:local_address().port)
  local reader, writer = client:reader(), client:writer()
  writer:write("hello\n")
  writer:flush()
  print(reader:read_line())
end)
-- Prints: hello!
```

A host name is resolved first. The addresses are then tried in the order the resolver gives:

- the next attempt starts after 250 milliseconds, or at once when an attempt fails;
- the first attempt to connect wins;
- the attempts that lose are cancelled.

The options are `nodelay` (default `true`), `keepalive` (default `false`), `keepalive_delay` and `family` (`"inet"`
or `"inet6"`). An unknown option raises `ArgumentError` before anything is resolved.

When no address connects, `connect` raises a `reactor.TransportError`. Its message names the host and the addresses
tried. `context.errno` is the libuv name of the last failure, for example `ECONNREFUSED`. `context.attempts` lists
every attempt. See [`net.connect`](../reference/net/functions/connect.md).

## Read and write

A [stream](../reference/glossary.md#concurrency) is an ordered sequence of bytes, read and written in order. In
practice you wrap it in a buffered reader and a buffered writer:

```lua
local reader, writer = stream:reader(), stream:writer()
```

The reader and the writer offer these calls:

- `reader:read_line()` returns one line without its line ending. It returns `nil` when the stream ended cleanly before
  any byte of a new line.
- `reader:read_until(delimiter)` returns the bytes before a delimiter.
- `reader:read_exact(count, limit)` returns exactly `count` bytes, or raises `EndOfStreamError` when the stream ends
  first. The bytes received stay in the reader (`context.buffered`).
- `writer:write(data)` adds to a buffer. Nothing is guaranteed to leave the process until `writer:flush()` returns.

Pass `limit` to `read_exact` when `count` comes from the [peer](../reference/glossary.md#concurrency), the other end
of the connection. A hostile peer then cannot make you buffer without bound.

Lines and records are limited to 65536 bytes by default. A longer one raises `ProtocolError`. Pass `{ limit = n }`
to `stream:reader()` to change it.

> [!TIP] One reader per stream
> `stream:reader()` creates a new reader each time. Two readers over one stream would split its bytes between them.
> Create one reader per stream and keep it.

You can also call `stream:read(max)` and `stream:write(data)` directly. `write` accepts all of `data` or raises. It
never returns a partial count.

## Close with `<close>`

Streams, listeners, readers and writers implement the Lua 5.5 `<close>` protocol. Declare them as
`local stream <close> = ...`, and they are closed when the block ends, even on an error or a cancellation.

`close` is idempotent. Closing a reader or a writer does not close the stream under it.

Closing a writer flushes what it still buffers, within `close_timeout` (5 seconds by default). It raises if the flush
fails or times out.

After `close`, any use raises `reactor.TransportError` with `context.errno` set to `EBADF`.

## Serve

`net.listen(host, port, options?)` binds an address and returns a `TcpListener`. Port `0` picks a free port;
`listener:local_address().port` tells you which.

`listener:accept()` suspends until a client connects and returns a `TcpStream`. A server loops on `accept` and forks
one coroutine per connection, so that a slow client never delays the others.

<!-- example: packages/net/examples/hecate.net.listen.lua -->
```lua
-- An accept loop that forks one coroutine per connection, so that a slow client
-- never delays the others. Two clients are served at the same time; the loop is
-- cancelled when they are done.
local reactor = require("hecate.reactor")
local net = require("hecate.net")

local function serve(connection)
  local peer <close> = connection
  local reader, writer = peer:reader(), peer:writer()
  while true do
    local line = reader:read_line()
    if line == nil then return end -- the client closed its end
    writer:write(line:upper() .. "\n")
    writer:flush()
  end
end

reactor.run(function()
  local listener <close> = net.listen("127.0.0.1", 0)
  local port = listener:local_address().port
  local acceptor = reactor.fork(function()
    while true do
      reactor.fork(serve, listener:accept())
    end
  end)
  local function ask(word)
    local client <close> = net.connect("127.0.0.1", port)
    local reader, writer = client:reader(), client:writer()
    writer:write(word .. "\n")
    writer:flush()
    return reader:read_line()
  end
  local first, second = reactor.join(reactor.fork(ask, "alpha"), reactor.fork(ask, "beta"))
  print(first .. " " .. second)
  -- Prints: ALPHA BETA
  acceptor:cancel()
end)
```

Cancelling an `accept` keeps the listener and the connections already queued in it. That is how the example stops its
loop: it cancels the future of the accept loop.

The options of `listen` are those of `connect`, plus `backlog` (default 128) and `reuseport`.

> [!NOTE] One name, several addresses
> `net.listen("localhost", port)` binds every address the resolver lists, usually `127.0.0.1` and `::1`, on the same
> port. `accept` takes connections from all of them. An address the machine cannot bind (no IPv6, for instance) is
> skipped. Pass a numeric address, or `family`, to bind just one.

> [!WARNING] `reuseport` is not usable yet
> `reuseport = true` lets several processes listen on one port. It raises `TransportError` with `ENOTSUP` today,
> because luv 1.53 does not expose it for TCP (OQ-43). Check `reactor.supports_reuseport()` first. See
> [Multi-process serving](../explanation/multi-process-serving.md#reuseport-does-not-work-yet).

## Half-close a connection

A [half-close](../reference/glossary.md#concurrency) ends one direction of a connection while the other stays usable.
A client that has sent its whole request can say so with `stream:shutdown()`. The peer then reads to the end of the
stream, while the client can still read the answer.

`shutdown` suspends. After it, the stream is still readable.

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

## Resolve a name

`net.resolve(host, options?)` returns the numeric addresses of a host, in the resolver's order. Use `family` to keep
only IPv4 or only IPv6.

```lua
local addresses = net.resolve("localhost", { family = "inet" })
print(addresses[1].ip)
-- Prints: 127.0.0.1
```

Name resolution runs on the libuv thread pool, which has four threads by default. Many slow resolutions can queue
behind each other, and there is no cache.

## Next steps

- [Deadlines and cancellation on streams](deadlines-and-cancellation.md)
- [TLS client and server](tls-client-and-server.md)
- [UDP, Unix sockets, named pipes and DNS](udp-pipes-and-dns.md)
- Reference: [`hecate.net`](../reference/net/index.md), [`TcpStream`](../reference/net/TcpStream.md),
  [`TcpListener`](../reference/net/TcpListener.md)
