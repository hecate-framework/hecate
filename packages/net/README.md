# `hecate-net`

> TCP/UDP streams, DNS resolution, buffered readers/writers and TLS, all suspending transparently.

| | |
|---|---|
| Module | `hecate.net` |
| Rock | `hecate-net` |
| Layer | 1 — Runtime |
| Roadmap phase | 1 |
| Status | in progress — `BufferedReader`, `BufferedWriter` and `Stream` implemented; TCP transport primitives now in `reactor` (OQ-28 resolved), `TcpStream`/`TcpListener` in `net` next; UDP, DNS, Unix sockets and TLS pending |
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
- DNS resolution through libuv
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

Not yet available: `TcpStream`, `TcpListener` (to be built on `reactor.tcp_connect` / `tcp_listen`), `UdpSocket`, DNS, Unix sockets, TLS.
Design choices of the buffered layer: OQ-29.

## Layout (once implemented)

```text
src/hecate/net/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
csrc/        native sources
```
