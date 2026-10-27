# `hecate-net`

> TCP/UDP streams, DNS resolution, buffered readers/writers and TLS, all suspending transparently.

| | |
|---|---|
| Module | `hecate.net` |
| Rock | `hecate-net` |
| Layer | 1 — Runtime |
| Roadmap phase | 1 |
| Status | alpha — buffered layer, TCP, UDP, pipes, name resolution and TLS (over rustls, needs the native module: `lua tools/run.lua build-native`) implemented; names are resolved through `reactor.resolve` (OQ-32), trust store: ADR 0024 |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`reactor`](../reactor) |
| Used by | `hecate`, `http`, `mongodb`, `mysql`, `postgresql`, `redis`, `sql`, `sqlserver`, `websocket` |
| Native code | Rust crate `native/` (rustls through mlua, [ADR 0021](../../docs/adr/0021-rust-native-modules.md)) |
| Specification | [networking.md](../../docs/architecture/networking.md) (transport in [concurrency.md](../../docs/architecture/concurrency.md)) |
| Decisions | [ADR 0002](../../docs/adr/0002-libuv-via-luv.md), [ADR 0003](../../docs/adr/0003-transparent-structured-concurrency.md), [ADR 0021](../../docs/adr/0021-rust-native-modules.md), [ADR 0024](../../docs/adr/0024-tls-trust-store.md) |
| Agent | [`pkg-net`](../../.claude/agents/pkg-net.md) |
| Repository | read-only mirror `hecate-framework/hecate-net`, generated from this directory (ADR 0017) |

## Responsibilities

- `TcpListener`, `TcpStream`, `UdpSocket`, Unix domain sockets / Windows named pipes
- `BufferedReader` (read line, read exact, read until) and `BufferedWriter`
- DNS resolution through libuv (`reactor.resolve`, exposed as `net.resolve`)
- TLS client and server (SNI, ALPN, certificate verification, mutual TLS)
- back-pressure and per-operation deadlines

## Non-goals

- application protocols (HTTP lives in `http`)

## Standards and references

- RFC 8446 (TLS 1.3)
- RFC 6125 (service identity)

## Public API

Functions marked *suspends* are `---@async` and raise `NonYieldableContextError` outside a managed coroutine.
Every example in the reference is a tested file of `examples/`.

### Streams and the buffered layer

| Name | Description |
|---|---|
| `net.Stream` | Interface of a transport: `read(max)` (*suspends*; nil at end of stream, never an empty string), `write(data)` (*suspends*; accepts all of `data` or raises, returns nothing), `close()` (idempotent, never suspends) and the `<close>` protocol. Optional: `shutdown()` (half-close), `is_closed()`. |
| `net.BufferedReader(stream, { limit })` | Reader over a stream; does not own it. `limit` bounds a line or record (default 65536 bytes). Options are checked: a table, only `limit`, a positive integer (`limit = false` is refused). |
| `reader:read_line(limit?)` | *suspends*. One line without its line feed (and the carriage return before it); nil at end of stream. |
| `reader:read_until(delimiter, limit?)` | *suspends*. Bytes before `delimiter`, which is consumed; nil at end of stream. `ProtocolError` beyond the limit. Linear in the record length however it is chunked. |
| `reader:read_exact(count, limit?)` | *suspends*. Exactly `count` bytes, or `EndOfStreamError`. With `limit`, a larger `count` raises `ProtocolError` before anything is read: pass it when `count` comes from a peer. |
| `reader:read_some(max?)` | *suspends*. Buffered bytes, or the next chunk; nil at end of stream. |
| `reader:buffered()`, `reader:close()`, `reader:is_closed()` | Bytes received but not consumed; discards them (idempotent, `<close>`-able). Reading after `close` raises `reactor.TransportError` (`EBADF`, `context.operation` the method name: `read_line`, `read_until`, `read_exact` or `read_some`). |
| `net.BufferedWriter(stream, { capacity })` | Writer over a stream; does not own it. Flushes at `capacity` bytes (default 8192, to be benchmarked; only `capacity` is accepted). A payload of at least `capacity` bytes written while nothing is buffered goes to the stream directly, without a copy. |
| `writer:write(data)`, `writer:flush()` | *suspend* when they flush. A failed or cancelled flush poisons the writer: later calls raise a `NetworkError` whose `cause` is the failure. |
| `writer:buffered()`, `writer:close()`, `writer:is_closed()` | Unflushed bytes; discards them without sending (idempotent, `<close>`-able): flush first. Writing after `close` raises `reactor.TransportError` (`EBADF`, `context.operation` `write` or `flush`). |
| `net.EndOfStreamError` | A `NetworkError`: the stream ended inside a read; `context.buffered` bytes stay in the reader. |
| `net.TransportError` | The failure of a transport operation: the very class `reactor.TransportError` (a `NetworkError`). |

### TCP

TCP over `reactor.connect_tcp` / `listen_tcp` / `resolve`; `net` never requires `luv`.

| Name | Description |
|---|---|
| `net.connect(host, port, options?)` | *suspends*. Resolves `host` (name or numeric address), tries its addresses in order, returns a `TcpStream`. Options (all optional, checked before anything is resolved; an unknown or invalid one raises `ArgumentError` naming `connect`): `nodelay` (boolean, default `true`), `keepalive` (boolean, default `false`), `keepalive_delay` (positive integer seconds, default 60), `family` (`"inet"`/`"inet6"`). When no address connects it raises a `reactor.TransportError` such as `net.connect: connect to example.org:5432 failed: ECONNREFUSED connection refused (tried 10.0.0.1, 10.0.0.2)`: `context.errno` is the libuv name, `context.host`, `context.port`, `context.attempts` (`{ address, errno }` of every attempt) and `cause` are set. A cancellation or deadline stops at once instead of trying the next address. |
| `net.listen(host, port, options?)` | *suspends* (resolution only). Binds the **first** resolved address (port 0 picks a free port): `listen("localhost", ...)` listens on whichever of `127.0.0.1` and `::1` the resolver lists first, so pass a numeric address or `family` when the address matters (binding every resolved address is decided, not implemented). Options as `connect` plus `backlog` (positive integer, default 128) and `reuseport` (boolean, see `reactor.supports_reuseport`). A failure reads `net.listen: listen on 0.0.0.0:8080 failed: EADDRINUSE address already in use` (same context as `connect`). |
| `net.TcpStream` | Implements `Stream`: `read(max?)` (*suspends*; nil at end of stream; `max` a positive integer; cancelling loses nothing), `write(data)` (*suspends*; back-pressure; a cancelled write closes the stream), `close()` (idempotent; `<close>`-able). Also `shutdown()` (*suspends*; half-close, stays readable), `is_closed()`, `peer_address()`, `local_address()` (`{ ip, port, family }`), `set_nodelay(bool)`, `set_keepalive(bool, delay?)`, `reader(options?)` and `writer(options?)` (a `BufferedReader` / `BufferedWriter` over the stream, which they do not own). |
| `net.TcpListener` | `accept()` (*suspends*; returns a `TcpStream`; cancelling keeps the listener and queued connections), `close()`, `is_closed()`, `local_address()`; `<close>`-able. |

Failures raise `reactor.TransportError`, a `core.NetworkError` that net lets propagate (`context.errno`: libuv name such as `ECONNREFUSED`, `EPIPE`, `EBADF` after close, `ECANCELED` when closed while waiting); `IoError` is not raised by net (OQ-32 (5)). Closed streams, readers and writers all raise the same `TransportError` with `EBADF`.

Per-operation deadlines use the reactor, there is no timeout argument:

```lua
local stream <close> = reactor.deadline(5, net.connect, "example.org", 80) -- resolution + connect
local reader = stream:reader()
local ok, err = pcall(reactor.deadline, 2, function() return reader:read_line() end)
-- On DeadlineExceededError the read was withdrawn: the stream and the reader are intact.
-- A write cancelled by a deadline closes the stream (bytes sent are unknown, OQ-30).
```

### Name resolution, datagrams and pipes

| Name | Description |
|---|---|
| `net.resolve(host, options?)` | *suspends*. A list of `{ ip, family }` entries in resolver order, never empty (`options.family`: `"inet"` or `"inet6"`). A failure is a `reactor.TransportError` whose message and `context.host` carry the name (`context.errno` is for example `EAI_NONAME`). |
| `net.bind_udp(host, port, options?)` | *suspends* (resolution only). A `UdpSocket` on the first resolved address; the only option is `family`. |
| `net.UdpSocket` | `send_to(host, port, data)` (*suspends*; one datagram; the destination first, like `connect`; **numeric address only**: a host name raises `ArgumentError` pointing to `net.resolve`, because a datagram has no connection to retry on another address), `receive_from()` (*suspends*; the payload, possibly empty, and the sender's `{ ip, port, family }`; cancelling loses no datagram), `local_address()`, `close()`, `is_closed()`; `<close>`-able. A cancelled `send_to` closes the socket; a closed socket raises `TransportError` (`EBADF`). |
| `net.listen_pipe(path, options?)` | Unix-domain socket (named pipe `\\.\pipe\name` on Windows); `path` must not exist. Does not suspend. Owner-only permissions are applied after the bind (creating the socket in a `0700` directory is decided, not implemented). Options: `backlog` (positive integer, default 128; ignored on Windows) and `mode` (who may connect: `"owner"`, the default, `"readable"`, `"writable"`, `"readwrite"`; no effect on Windows). A Windows pipe name is limited to 256 characters and a Unix socket path to the platform's `sun_path` (at most 107 bytes, 103 on macOS, excluding the terminating NUL): a longer one raises `ArgumentError`. Returns a `PipeListener`. |
| `net.connect_pipe(path)` | *suspends*. A `PipeStream`. |
| `net.PipeStream` | Same stream and buffered API as `TcpStream` (`read`, `write`, `shutdown`, `close`, `is_closed`, `reader`, `writer`) plus `path()`. |
| `net.PipeListener` | `accept()` (*suspends*; cancelling keeps the listener), `close()`, `is_closed()`, `path()`; `<close>`-able. |

The behaviour, defaults, limits, error classes and cancellation rules are specified in [networking.md](../../docs/architecture/networking.md); the choices behind them are OQ-29, OQ-30, OQ-32, OQ-42 and OQ-47.

## TLS

Implemented over `rustls` in a native module (ADR 0021, OQ-41); trust store, verification, errors and handshake
deadlines are specified in [networking.md](../../docs/architecture/networking.md#tls). Build the module with a Rust
toolchain: `lua tools/run.lua build-native` (installs into `.hecate/rocks`; macOS link flags are in
`native/.cargo/config.toml`; on Windows set `LUA_LIB_NAME`, `LUA_LIB` and `LUA_INC` first). Installed rocks will ship
the module once distribution lands. Without it, `net.tls.available()` is false and TLS calls raise `TlsError`
(`context.reason = "native_missing"`).

Certificate verification is on and cannot be turned off; the operating system's trust store is used (ADR 0024),
`ca_pem` adds anchors and `system_roots = false` trusts only `ca_pem`. Server-side revocation of client certificates
is not checked yet (a CRL option is decided, see the specification).

| Name | Description |
|---|---|
| `net.connect_tls(host, port, options?)` | *suspends*. `net.connect` then a TLS handshake. Every option is optional. Transport: `nodelay`, `keepalive`, `keepalive_delay`, `family` (as `connect`). TLS: `ca_pem` (added to the system store), `system_roots` (false trusts only `ca_pem`), `alpn` (non-empty list of non-empty strings of at most 255 bytes), `cert_pem` and `key_pem` (mutual TLS, together), `server_name` (default `host`: SNI and identity), `tls_config` (a prebuilt configuration, exclusive with the other TLS options), `handshake_deadline` (seconds, default 10: expiry raises the deadline error and closes the stream). |
| `net.tls.accept(stream, config, options?)` | *suspends*. `options.handshake_deadline` (seconds, default 10 today; 60 is decided, see the specification) bounds the handshake. The server side: `tls.accept(listener:accept(), config)` runs the handshake of one accepted connection and takes ownership of the stream once its arguments are valid. This two-step form is the idiom, on purpose: fork the handshake per connection so that one slow or silent client cannot stall the accept loop (`handshake_deadline` bounds it anyway). |
| `net.tls.client_config(options?)`, `net.tls.server_config(options)` | Reusable configurations (client: `ca_pem`, `system_roots`, `alpn`, `cert_pem`, `key_pem`; server: `cert_pem`, `key_pem`, `alpn`, `client_ca_pem` to require client certificates). |
| `net.tls.connect(stream, server_name, config, options?)` | *suspends*. `options.handshake_deadline` (seconds, default 10) bounds the handshake. Handshake over an existing stream, which the result owns (the caller keeps it when an argument is malformed). |
| `net.TlsStream` | Implements `Stream`; `handshake()`, `shutdown()` (sends `close_notify`, *suspends*), `alpn()`, `requested_server_name()` (the SNI a client sent; nil on client streams), `version()`, `peer_certificate()`, `peer_address()`, `local_address()` and `set_nodelay(bool)` (forwarded to the inner stream), `reader()`, `writer()`, `is_closed()`. `read` returns nil after the peer's `close_notify` and raises `TlsError` when the transport ends without it. `close()` cannot send `close_notify`: call `shutdown()` first. A closed stream raises `reactor.TransportError` (`EBADF`). |
| `net.TlsError` | A `NetworkError`: failed handshake or verification, protocol failure, truncation, module not built. `context.reason` names the kind when it is recognised (`untrusted_issuer`, `name_mismatch`, `expired`, `not_yet_valid`, `revoked`, `alpn_mismatch`, `truncated`, `transport_ended`, `stalled`, `native_missing`); the operating system's verifiers on macOS and Windows report many failures as text only. |

## Layout

```text
src/hecate/net/init.lua   public entry point (tcp, udp, pipe, dns, tls and the buffered layer beside it)
tests/unit/               in-memory tests (buffered layer, API surface, examples)
tests/integration/        loopback tests (TCP, UDP, pipes, TLS against a local test CA)
tests/fixtures/           throwaway TLS certificates and keys
examples/                 one tested file per documented symbol (hecate.net.<symbol>.lua)
native/                   Rust crate of the TLS module (Cargo.lock committed)
```

Micro-benchmarks (`benchmarks/`, run with `lua tools/run.lua bench net`): `read-until` (`read_line` over many small chunks), `buffered-writer` (small coalesced writes and 1 MiB payloads) and `tls-throughput` (one TLS stream, needs the native module). The network scenario `tcp-echo` of the repository-level harness exercises `net` and the reactor under 10 000 connections (`lua tools/run.lua bench tcp-echo`).
