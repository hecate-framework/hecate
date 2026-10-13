# `hecate-net`

> TCP/UDP streams, DNS resolution, buffered readers/writers and TLS, all suspending transparently.

| | |
|---|---|
| Module | `hecate.net` |
| Rock | `hecate-net` |
| Layer | 1 — Runtime |
| Roadmap phase | 1 |
| Status | in progress — `BufferedReader`, `BufferedWriter`, `Stream`, `TcpStream`, `TcpListener`, `connect` and `listen` implemented (names resolved through `reactor.resolve`, OQ-32); UDP, Unix sockets and TLS pending |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`reactor`](../reactor) |
| Used by | `hecate`, `http`, `mongodb`, `mysql`, `postgresql`, `redis`, `sql`, `sqlserver`, `websocket` |
| Native code | TLS library binding (OQ-4) |
| Specification | [concurrency.md](../../docs/architecture/concurrency.md) |
| Decisions | [ADR 0002](../../docs/adr/0002-libuv-via-luv.md), [ADR 0003](../../docs/adr/0003-transparent-structured-concurrency.md) |
| Agent | [`pkg-net`](../../.claude/agents/pkg-net.md) |
| Repository | read-only mirror `hecate-framework/hecate-net`, generated from this directory (ADR 0017) |

## Responsibilities

- `TcpListener`, `TcpStream`, `UdpSocket`, Unix domain sockets / Windows named pipes
- `BufferedReader` (read line, read exact, read until) and `BufferedWriter`
- DNS resolution through libuv (`reactor.resolve`; a `net` resolver API is pending)
- TLS client and server (SNI, ALPN, certificate verification, mutual TLS)
- back-pressure and per-operation deadlines

## Non-goals

- application protocols (HTTP lives in `http`)

## Standards and references

- RFC 8446 (TLS 1.3)
- RFC 6125 (service identity)

## Public API

Implemented (step 1). Functions marked *suspends* are `---@async` and raise
`NonYieldableContextError` outside a managed coroutine.

| Name | Description |
|---|---|
| `net.Stream` | Interface of a transport: `read(max)` (*suspends*; nil at end of stream), `write(data)` (*suspends*; accepts all of `data` or raises), `close()` (idempotent). |
| `net.BufferedReader(stream, { limit })` | Reader over a stream; does not own it. `limit` bounds a line or record (default 65536 bytes). |
| `reader:read_line(limit)` | *suspends*. One line without its line feed (and the carriage return before it); nil at end of stream. |
| `reader:read_until(delimiter, limit)` | *suspends*. Bytes before `delimiter`, which is consumed; nil at end of stream. `ProtocolError` beyond the limit. |
| `reader:read_exact(count)` | *suspends*. Exactly `count` bytes, or `EndOfStreamError`. |
| `reader:read_some(max)` | *suspends*. Buffered bytes, or the next chunk; nil at end of stream. |
| `reader:buffered()`, `reader:close()` | Bytes received but not consumed; discards them (idempotent, `<close>`-able). |
| `net.BufferedWriter(stream, { capacity })` | Writer over a stream; does not own it. Flushes at `capacity` bytes (default 8192). |
| `writer:write(data)`, `writer:flush()` | *suspend* when they flush. A failed flush poisons the writer: later calls raise the same error. |
| `writer:buffered()`, `writer:close()` | Unflushed bytes; discards them without sending (idempotent, `<close>`-able): flush first. |
| `net.EndOfStreamError` | A `NetworkError`: the stream ended inside a read; `context.buffered` bytes stay in the reader. |

Implemented (step 3). TCP over `reactor.tcp_connect` / `tcp_listen` / `resolve`; `net` never requires `luv`.

| Name | Description |
|---|---|
| `net.connect(host, port, options?)` | *suspends*. Resolves `host` (name or numeric address), tries its addresses in order, returns a `TcpStream`; raises the last `IoError` when all fail. Options: `nodelay` (default `true`), `keepalive` (default `false`), `keepalive_delay` (seconds, default 60), `family` (`"inet"`/`"inet6"`). |
| `net.listen(host, port, options?)` | *suspends* (resolution only). Binds the first resolved address (port 0 picks a free port); returns a `TcpListener`. Options as above plus `backlog` (default 128). |
| `net.TcpStream` | Implements `Stream`: `read(max?)` (*suspends*; nil at end of stream; cancelling loses nothing), `write(data)` (*suspends*; back-pressure; a cancelled write closes the stream), `close()` (idempotent; `<close>`-able). Also `shutdown()` (*suspends*; half-close, stays readable), `is_closed()`, `peer_address()`, `local_address()` (`{ ip, port, family }`), `set_nodelay(bool)`, `set_keepalive(bool, delay?)`, `reader(options?)` and `writer(options?)` (a `BufferedReader` / `BufferedWriter` over the stream, which they do not own). |
| `net.TcpListener` | `accept()` (*suspends*; returns a `TcpStream`; cancelling keeps the listener and queued connections), `close()`, `is_closed()`, `local_address()`; `<close>`-able. |

Failures raise `reactor.IoError` (`context.errno`: libuv name such as `ECONNREFUSED`, `EPIPE`, `EBADF` after close, `ECANCELED` when closed while waiting); mapping to `NetworkError` is OQ-32 (5).

Per-operation deadlines use the reactor, there is no timeout argument:

```lua
local stream <close> = reactor.deadline(5, net.connect, "example.org", 80) -- resolution + connect
local reader = stream:reader()
local ok, err = pcall(reactor.deadline, 2, function() return reader:read_line() end)
-- On DeadlineExceededError the read was withdrawn: the stream and the reader are intact.
-- A write cancelled by a deadline closes the stream (bytes sent are unknown, OQ-30).
```

Not yet available: `UdpSocket`, a `net` resolver API, Unix sockets, TLS.
Design choices of the buffered layer: OQ-29; of TCP and resolution: OQ-30, OQ-32.

## Layout (once implemented)

```text
src/hecate/net/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
csrc/        native sources
```
