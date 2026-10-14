# `hecate-net`

> TCP/UDP streams, DNS resolution, buffered readers/writers and TLS, all suspending transparently.

| | |
|---|---|
| Module | `hecate.net` |
| Rock | `hecate-net` |
| Layer | 1 — Runtime |
| Roadmap phase | 1 |
| Status | in progress — `BufferedReader`, `BufferedWriter`, `Stream`, `TcpStream`, `TcpListener`, `connect`, `listen`, `UdpSocket`, `bind_udp`, `PipeStream`, `PipeListener`, `connect_pipe` and `listen_pipe` implemented (names resolved through `reactor.resolve`, OQ-32); TLS implemented over rustls (client and server, SNI, ALPN, mutual TLS; trust store: OQ-41), needs the native module (`lua tools/run.lua build-native`) |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`reactor`](../reactor) |
| Used by | `hecate`, `http`, `mongodb`, `mysql`, `postgresql`, `redis`, `sql`, `sqlserver`, `websocket` |
| Native code | Rust crate `native/` (rustls through mlua, [ADR 0021](../../docs/adr/0021-rust-native-modules.md)) |
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
| `net.connect(host, port, options?)` | *suspends*. Resolves `host` (name or numeric address), tries its addresses in order, returns a `TcpStream`; raises the last `reactor.TransportError` when all fail. Options: `nodelay` (default `true`), `keepalive` (default `false`), `keepalive_delay` (seconds, default 60), `family` (`"inet"`/`"inet6"`). |
| `net.listen(host, port, options?)` | *suspends* (resolution only). Binds the first resolved address (port 0 picks a free port); returns a `TcpListener`. Options as above plus `backlog` (default 128). |
| `net.TcpStream` | Implements `Stream`: `read(max?)` (*suspends*; nil at end of stream; cancelling loses nothing), `write(data)` (*suspends*; back-pressure; a cancelled write closes the stream), `close()` (idempotent; `<close>`-able). Also `shutdown()` (*suspends*; half-close, stays readable), `is_closed()`, `peer_address()`, `local_address()` (`{ ip, port, family }`), `set_nodelay(bool)`, `set_keepalive(bool, delay?)`, `reader(options?)` and `writer(options?)` (a `BufferedReader` / `BufferedWriter` over the stream, which they do not own). |
| `net.TcpListener` | `accept()` (*suspends*; returns a `TcpStream`; cancelling keeps the listener and queued connections), `close()`, `is_closed()`, `local_address()`; `<close>`-able. |

Failures raise `reactor.TransportError`, a `core.NetworkError` that net lets propagate unchanged (`context.errno`: libuv name such as `ECONNREFUSED`, `EPIPE`, `EBADF` after close, `ECANCELED` when closed while waiting); `IoError` is not raised by net (OQ-32 (5)).

Per-operation deadlines use the reactor, there is no timeout argument:

```lua
local stream <close> = reactor.deadline(5, net.connect, "example.org", 80) -- resolution + connect
local reader = stream:reader()
local ok, err = pcall(reactor.deadline, 2, function() return reader:read_line() end)
-- On DeadlineExceededError the read was withdrawn: the stream and the reader are intact.
-- A write cancelled by a deadline closes the stream (bytes sent are unknown, OQ-30).
```

Unix-domain sockets (named pipes on Windows): `net.listen_pipe(path)` and `net.connect_pipe(path)` give `PipeListener`/`PipeStream`, with the same stream and buffered API as TCP.

Datagrams: `net.bind_udp(host, port)` returns a `UdpSocket` (`send_to`, `receive_from`).

Not yet available: a `net` resolver API.
Design choices of the buffered layer: OQ-29; of TCP and resolution: OQ-30, OQ-32.

## TLS

Implemented (step 6; ADR 0021, choices in OQ-41). `rustls` runs sans-IO inside a native module
(`hecate.net.tls_native`); `TlsStream` moves bytes between it and an inner `Stream`, so all
suspension stays in the reactor. Build the module with a Rust toolchain:
`lua tools/run.lua build-native` (installs into `.hecate/rocks`; macOS link flags are in
`native/.cargo/config.toml`; on Windows set `LUA_LIB_NAME`, `LUA_LIB` and `LUA_INC` first).
Without it, `net.tls.available()` is false and TLS calls raise `TlsError`.

Certificate verification is on and cannot be turned off (RFC 8446 section 4.4.2, RFC 6125).
There is no built-in trust store yet: pass the trust anchors as `ca_pem`.

| Name | Description |
|---|---|
| `net.connect_tls(host, port, options)` | *suspends*. `net.connect` then a TLS handshake. Options: those of `connect` plus `ca_pem` (required unless `tls_config`), `alpn`, `cert_pem` and `key_pem` (mutual TLS), `server_name` (default `host`: SNI and identity), `tls_config`. |
| `net.tls.client_config(options)`, `net.tls.server_config(options)` | Reusable configurations (`ca_pem`, `alpn`, `cert_pem`, `key_pem`; server: `cert_pem`, `key_pem`, `alpn`, `client_ca_pem` to require client certificates). |
| `net.tls.connect(stream, server_name, config)`, `net.tls.accept(stream, config)` | *suspend*. Handshake over an existing stream, which the result owns. |
| `net.TlsStream` | Implements `Stream`; `handshake()`, `shutdown()` (sends `close_notify`, *suspends*), `alpn()`, `server_name()`, `version()`, `peer_certificate()`, `reader()`, `writer()`, `is_closed()`. `read` returns nil after the peer's `close_notify` and raises `TlsError` when the transport ends without it. `close()` cannot send `close_notify`: call `shutdown()` first. |
| `net.TlsError` | A `NetworkError`: failed handshake or verification, protocol failure, truncation, module not built. |

## Layout (once implemented)

```text
src/hecate/net/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
native/      Rust crate of the TLS module (Cargo.lock committed)
```
