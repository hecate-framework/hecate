# Networking (`hecate.net`)

Package: `net` (layer 1, Runtime). Status: specification of the implemented behaviour (alpha) and of the decided
contract; decisions in [ADR 0002](../adr/0002-libuv-via-luv.md) (luv wrapped once, in `reactor`),
[ADR 0003](../adr/0003-transparent-structured-concurrency.md) (suspension),
[ADR 0018](../adr/0018-error-signalling.md) (errors), [ADR 0021](../adr/0021-rust-native-modules.md) (native modules)
and [ADR 0024](../adr/0024-tls-trust-store.md) (TLS trust store, Accepted); the choices of the first implementation
are recorded in [OQ-29, OQ-30, OQ-32, OQ-41, OQ-42 and OQ-47](../open-questions.md). Where a statement describes
something that is decided but not implemented, it says so, and the "Decided, not yet implemented" section lists
them (the `net` follow-up of the [roadmap](../roadmap.md)).

## Scope and layering

`hecate.net` moves bytes and datagrams between processes: TCP streams and listeners, UDP sockets, local stream
sockets (Unix-domain sockets, named pipes on Windows), name resolution, TLS, and the buffered reader and writer
that application protocols read and write through. Its dependencies are `core` and `reactor`.

- **`net` never requires `luv`.** The transport primitives (`connect_tcp`, `listen_tcp`, `bind_udp`,
  `connect_pipe`, `listen_pipe`, `resolve`) live in `hecate.reactor` ([concurrency.md](concurrency.md), "Transport";
  OQ-28). `net` wraps them, validates its own options, resolves names, renames the call in error messages, and adds
  the buffered layer and TLS. `check-boundaries` enforces it; tests may use `luv` to spy on handles, `src` may not.
- **Suspension is transparent.** Functions that may suspend are annotated `---@async` and raise
  `NonYieldableContextError` outside a managed coroutine. Nothing in `net` blocks the reactor, except the
  operating-system certificate verifier on macOS and Windows (see "TLS", "Trust").
- **TLS runs sans-IO.** `rustls` lives inside a native module (`hecate.net.tls_native`, Rust crate `native/`);
  the Lua class `TlsStream` moves bytes between it and an inner `Stream`, so every suspension happens in the reactor.
- Application protocols (HTTP, database wire protocols) are **not** in `net`; they read and write through the
  `Stream` interface and the buffered layer.

Non-goals: application protocols; connection pooling (a driver concern); parallel connection attempts across
addresses (RFC 8305, Happy Eyeballs) and a resolver cache (OQ-32); SOCKS or HTTP proxies; certificate-based
server selection by SNI on the server (a single certificate per configuration); session resumption configuration,
OCSP stapling policy and 0-RTT (OQ-41); datagram truncation and loss semantics (OQ-42 (8)); a non-blocking file
API (that is `reactor.fs`).

## The Stream interface

`net.Stream` is the contract between the buffered layer and a transport. It is an interface of `hecate.core`
(`core.interface("Stream", { "read", "write", "close" })`): a transport implements the three methods and the
`<close>` protocol.

| Member | Contract |
|---|---|
| `read(max?)` | *suspends*. At most `max` bytes (a positive integer; no argument means a transport-chosen amount), what one receive delivered; `nil` at end of stream; **never an empty string**. |
| `write(data)` | *suspends*. Accepts all of `data` or raises; returns nothing. Suspends while the peer is slower (back-pressure). |
| `close()` | Idempotent, never suspends. Also the `__close` metamethod. Abandons pending bytes. |
| `shutdown()` | Optional, *suspends*. Half-close: no more data will be written, the stream stays readable. |
| `is_closed()` | Optional. |

Implementations: `TcpStream`, `PipeStream`, `TlsStream`. `UdpSocket` is **not** a stream: a datagram is a unit,
not a sequence of bytes.

Invariants, checked by tests that walk every class:

- every stream, listener, socket, reader and writer is `<close>`-able (`close`, `__close`, `is_closed`);
- a closed object raises `reactor.TransportError` with `errno = "EBADF"` and a stable `context.operation`;
- a partial read or write never leaks: a call returns a complete result or raises, and what was received stays
  buffered (see "Cancellation rules").

One coroutine reads at a time on a stream, a listener or a `UdpSocket`; a second concurrent call raises
`core.Error` instead of waiting. Writes from several coroutines on a `TcpStream` are queued in call order; on a
`TlsStream` they run one after the other, each intact. (`BufferedReader` and `BufferedWriter` behave differently:
they queue, see below.)

## Buffered reader and writer

A reader or writer wraps any `Stream` and **does not own it**: closing the reader or writer never closes the stream
(OQ-29 (6)). `stream:reader(options?)` and `stream:writer(options?)` on `TcpStream`, `PipeStream` and `TlsStream`
create a new wrapper per call; several readers over one stream split its bytes, so one reader per stream is the
rule, not enforced (OQ-32 (7)).

### BufferedReader

`net.BufferedReader(stream, { limit? })`. The options are checked: a table, only `limit`, a positive integer
(`limit = false` is refused; there is no unlimited mode).

| Method | Behaviour |
|---|---|
| `read_line(limit?)` | *suspends*. One line without its line feed and without the carriage return before it (one only). `nil` at end of stream with nothing buffered. |
| `read_until(delimiter, limit?)` | *suspends*. The bytes before `delimiter`, which is consumed; the delimiter is a non-empty string. Linear in the record length however the peer chunks it. |
| `read_exact(count, limit?)` | *suspends*. Exactly `count` bytes. With `limit`, a larger `count` raises `ProtocolError` before anything is read: pass it when `count` comes from a peer. Without it `count` is the caller's own and is not bounded. |
| `read_some(max?)` | *suspends*. What is buffered (at most `max`), or the next chunk; `nil` at end of stream. |
| `buffered()` | Bytes received and not consumed. |
| `close()`, `is_closed()` | Discards the buffered bytes; idempotent. Any read afterwards raises `TransportError` (`EBADF`, `context.operation` is `read_line`, `read_until`, `read_exact` or `read_some`). |

Rules:

- The stream is read in chunks of 16 KiB.
- `limit` (default **65536 bytes**) bounds a line or delimited record. A record longer than the limit raises
  `core.ProtocolError` (`context.limit`); the check fires once the buffer holds the limit plus the delimiter
  length, so the buffer may hold up to one chunk (16 KiB) more than the limit before it does.
- End of stream on an empty buffer returns `nil`. End of stream **inside** a record raises
  `net.EndOfStreamError` (a `NetworkError`; `context.buffered`, and `context.wanted` for `read_exact`); the bytes
  stay in the reader.
- Each reader serialises its operations with a `reactor.Mutex`: a second concurrent call waits for its turn
  instead of raising (OQ-29 (7)).

### BufferedWriter

`net.BufferedWriter(stream, { capacity? })`; only `capacity` is accepted, a positive integer.

| Method | Behaviour |
|---|---|
| `write(data)` | Appends `data` (a string); flushes when the buffer reaches `capacity`. Suspends only when it flushes. A payload of at least `capacity` bytes written while nothing is buffered and no flush is running goes to the stream directly, without a copy: same ordering and failure rules. |
| `flush()` | *suspends*. Hands the buffered bytes to the stream; returns when the stream accepted them all. |
| `buffered()` | Bytes accepted and not flushed. |
| `close()`, `is_closed()` | Discards unflushed bytes without sending them (flush first); idempotent. Writing afterwards raises `TransportError` (`EBADF`, `context.operation` is `write` or `flush`). |

Rules:

- **Poisoning.** A failed or cancelled flush (or direct write) poisons the writer, because the number of bytes
  the peer received is unknown: every later call raises a `NetworkError` whose `cause` is the original failure,
  rather than sending bytes after a gap (OQ-29 (4)).
- **`close` discards.** `close` and `__close` never flush, because a close handler must not suspend while its scope
  is cancelled (OQ-23, OQ-29 (5)). *Decided, not implemented:* once `reactor.shield(fn)` exists (roadmap,
  `reactor` follow-up), `BufferedWriter:close` can flush under a shield with its own deadline.
- Flushes are serialised by a `reactor.Mutex`, which keeps bytes in order.
- Flush a writer before `shutdown`.
- The default `capacity` is **8192 bytes**, below one TLS record (16 KiB of plaintext). *Decided, not
  implemented:* a benchmark decides the default, compared with other frameworks (Go's `bufio` uses 4 KiB); the
  micro-benchmark `buffered-writer` exists (OQ-47 (7), owner answer of 2026-10-27). Until then 8 KiB stays and
  `{ capacity = n }` overrides it.

## Addresses and name resolution

An address is `{ ip, port, family }` (`family` is `"inet"` or `"inet6"`); a resolved entry is `{ ip, family }`.

`net.resolve(host, options?)` *suspends*. It returns a list of entries in the system resolver's order, never empty;
a numeric address resolves to itself; `options.family` restricts the answer. It runs on libuv's `getaddrinfo`,
which uses the thread pool (four threads by default): many slow resolutions queue behind each other, and there is
no cache (OQ-32 (8)). A cancelled resolution is released at once and its late result discarded. A failure is a
`reactor.TransportError` whose message and `context.host` carry the name and whose `context.errno` is the
resolver's code (for example `EAI_NONAME`).

Every function that takes a host (`connect`, `listen`, `bind_udp`, `connect_tls`) resolves it through this function,
so the failures name the call the caller wrote.

## TCP

`net.connect(host, port, options?)` *suspends* and returns a `TcpStream`.

- Options (all optional, validated before anything is resolved; an unknown or invalid one raises `ArgumentError`
  naming `net.connect`): `nodelay` (boolean, default `true`: Nagle off), `keepalive` (boolean, default `false`),
  `keepalive_delay` (positive integer seconds, default 60), `family`.
- The port is an integer in 0..65535; the host a non-empty string.
- The addresses are tried **in resolver order, one after the other**, with no per-attempt deadline. A
  cancellation or deadline stops at once instead of trying the next address. When none connects, the call raises a
  `reactor.TransportError` of the last failure, with the message naming the endpoint and the attempts
  (`net.connect: connect to example.org:5432 failed: ECONNREFUSED connection refused (tried 10.0.0.1, 10.0.0.2)`);
  `context.errno`, `context.host`, `context.port`, `context.attempts` (`{ address, errno }` per attempt) and
  `cause` are set.

`net.listen(host, port, options?)` *suspends* (resolution only) and returns a `TcpListener`. Options: those of
`connect` plus `backlog` (positive integer, default 128) and `reuseport` (boolean; see `reactor.supports_reuseport`).
Port 0 picks a free port (`listener:local_address()`). Accepted streams inherit the listener's `nodelay` and
`keepalive` options (OQ-30 (4)).

- **Implemented: the first resolved address only is bound.** `listen("localhost", ...)` listens on whichever of
  `127.0.0.1` and `::1` the resolver lists first. Pass a numeric address or `family` when the address matters.
- **Decided, not implemented** (owner, 2026-10-27, OQ-47 (5); supersedes OQ-32 (3)): bind **every** resolved
  address, so that `localhost` serves `::1` and `127.0.0.1`. The listener then has one handle per address;
  `local_address()`, `accept()` and `close()` are to be specified with the implementation (see "Open points").
- A bind failure reads `net.listen: listen on 0.0.0.0:8080 failed: EADDRINUSE address already in use` (same
  context as `connect`).
- `reuseport` is accepted, but its branch cannot run in CI until luv supports TCP `reuseport` (OQ-43, OQ-47 (8)).

`TcpStream` implements `Stream`:

| Member | Behaviour |
|---|---|
| `read(max?)` | `nil` at end of stream; `max` a positive integer. Reads ahead up to 64 KiB, then stops reading from the socket until the reader caught up (back-pressure; OQ-47 (1), confirmed). |
| `write(data)` | Suspends under back-pressure. |
| `shutdown()` | *suspends*. Half-close, once pending writes are flushed; stays readable. |
| `close()`, `is_closed()` | Wakes every coroutine waiting on the stream with `errno = "ECANCELED"`. A stream that is not closed explicitly keeps its libuv handle open: there is no finaliser (OQ-30 (9)). |
| `peer_address()`, `local_address()` | `{ ip, port, family }`. |
| `set_nodelay(bool)`, `set_keepalive(bool, delay?)` | Change the options of an open stream. |
| `reader(options?)`, `writer(options?)` | Buffered wrappers. |

`TcpListener`: `accept()` (*suspends*, returns a `TcpStream`; one coroutine at a time; connections are taken one per
call, so a slow acceptor leaves the rest in the kernel backlog), `close()` (a coroutine waiting in `accept` fails
with `ECANCELED`; accepted streams are unaffected), `is_closed()`, `local_address()`. A read error is sticky (raised
again by later reads); an accept error is raised once (OQ-30 (7)).

## UDP

`net.bind_udp(host, port, options?)` *suspends* (resolution only) and returns a `UdpSocket` bound on the first
resolved address; the only option is `family`. The port is 0..65535.

`UdpSocket`:

- `send_to(host, port, data)` *suspends*. One datagram; the destination first, like `connect` (owner decision,
  2026-10-18). `host` is a **numeric address only**: a name raises `ArgumentError` that points to `net.resolve`,
  because a datagram has no connection to retry on another address. `port` is 1..65535, `data` a string.
- `receive_from()` *suspends*. The payload (possibly empty) and the sender's `{ ip, port, family }`. One coroutine
  at a time.
- `local_address()`, `close()`, `is_closed()`; `<close>`-able.
- There is no `IPV6_V6ONLY` option: `::` is dual-stack on Linux and macOS and v6-only on Windows by default
  (OQ-42 (7)).

## Pipes (Unix-domain sockets, named pipes)

`net.connect_pipe(path)` *suspends* and returns a `PipeStream`. `net.listen_pipe(path, options?)` does not suspend
and returns a `PipeListener`.

- `path` must not exist when listening; a stale socket file is **not** removed (`EADDRINUSE`), and libuv unlinks
  the path when the listener closes (OQ-42 (5)).
- Options: `backlog` (positive integer, default 128; ignored on Windows) and `mode` (who may connect: `"owner"`,
  the default, `"readable"`, `"writable"`, `"readwrite"`; no effect on Windows, where the default security of the
  pipe applies).
- A Windows pipe name (`\\.\pipe\name`) is limited to 256 characters; a Unix socket path to the platform's
  `sun_path`: 107 bytes on Linux, 103 on macOS, excluding the terminating NUL. A longer path raises `ArgumentError`
  in both functions (OQ-42 (6)).
- `PipeStream` has the same stream and buffered API as `TcpStream` (`read`, `write`, `shutdown`, `close`,
  `is_closed`, `reader`, `writer`) plus `path()`; `PipeListener` has `accept()`, `close()`, `is_closed()`,
  `path()`. The cancellation rules are those of TCP.
- **Implemented: owner-only permissions are applied after the bind.** `mode = "owner"` makes the socket file
  `0600` right after binding: for a very short window the file has the permissions of the umask (libuv can only
  open it to everyone). **Decided, not implemented** (owner, 2026-10-27, OQ-47 (4), a breach recipe): create the
  socket inside a directory of mode `0700` (or an equivalent that never exposes it), instead of binding then
  calling `chmod`. Until then, put the socket in a directory that only the owner can enter.
- A `PipeStream` is not a message pipe: the framed, process-to-process `reactor.ipc` connection (glossary: message
  pipe) belongs to `reactor`. Its frame size limit, `max_message`, defaults to 16 MiB and is an option per peer
  (`reactor.Peer`); it stays editable (OQ-47 (3), owner answer of 2026-10-27) and does not read ahead.

## TLS

Implemented over `rustls` in a native module (ADR 0021, OQ-41), built with `lua tools/run.lua build-native`.
`net.tls.available()` returns `true`, or `false` and the reason. Without the module every TLS call raises `TlsError`
with `context.reason = "native_missing"`. Protocol versions are the rustls defaults (TLS 1.3 and 1.2, RFC 8446); the
crypto provider is `ring`.

### Certificate verification

Verification is on and **cannot be turned off** (RFC 8446 section 4.4.2, RFC 6125): no option installs a verifier
that accepts everything, and options that other libraries use for that purpose (`verify`, `insecure`,
`skip_verify`, `danger_accept_invalid_certs`) are refused with an `ArgumentError` that says so. Options are checked
against an allow-list per function; an unknown or misplaced key (`ca_pem` on a server configuration,
`client_ca_pem` on a client one) raises `ArgumentError` naming the kind of configuration the option belongs to.

### Trust

[ADR 0024](../adr/0024-tls-trust-store.md), Accepted:

- the server certificate is verified by the operating system's verifier (`rustls-platform-verifier`), so a public
  server works with no option;
- `ca_pem` **adds** trust anchors (a private CA); `system_roots = false` trusts only `ca_pem` (it requires
  `ca_pem`) and uses the platform-independent verifier, with no I/O and none of the operating system's policy;
- an empty or incomplete system store is an error, never a silent fallback: a handshake that fails with an unknown
  issuer raises `TlsError` (`reason = "untrusted_issuer"`) whose message gives the remedy (install the system CA
  certificates, or pass `ca_pem`); Docker runtime images install `ca-certificates`;
- on macOS and Windows the verifier may check revocation over the network inside the handshake, which blocks the
  reactor until the responder answers; Linux does no revocation checking; macOS refuses a server certificate valid
  for more than 398 days even when its CA was added with `ca_pem` (ADR 0024).

### Configurations and entry points

A configuration built once can be reused across connections. `net.tls.client_config(options?)`:

| Option | Meaning |
|---|---|
| `ca_pem` | PEM trust anchors, added to the system store. |
| `system_roots` | Boolean, default `true`. |
| `alpn` | Non-empty list of non-empty strings of at most 255 bytes (RFC 7301). |
| `cert_pem`, `key_pem` | Client certificate chain and private key (mutual TLS); only together. |

`net.tls.server_config(options)`:

| Option | Meaning |
|---|---|
| `cert_pem`, `key_pem` | Required: certificate chain (end-entity first) and private key. |
| `alpn` | Accepted protocols, in preference order. |
| `client_ca_pem` | Require and verify client certificates against these anchors. |

Entry points (all *suspend*):

- `net.connect_tls(host, port, options?)`: `net.connect`, then the handshake. Options: the transport options of
  `connect`; the client options; `server_name` (default `host`: SNI and identity, RFC 6125); `tls_config` (a
  prebuilt configuration, exclusive with the other TLS options); `handshake_timeout`. Every option is validated
  before any name is resolved. Without `tls_config` a configuration is built per call; the default one (system
  roots, no `ca_pem`, no client certificate) is cached per `alpn` list (at most 16 lists).
- `net.tls.connect(stream, server_name, config, options?)`: the handshake over an existing `Stream`.
- `net.tls.accept(stream, config, options?)`: the server handshake over an accepted stream. The two-step form
  `tls.accept(listener:accept(), config)` is the idiom, on purpose: fork the handshake per connection so that one
  slow or silent client cannot stall the accept loop.
- Both `tls.connect` and `tls.accept` take ownership of the stream **once their arguments are valid**: when an
  argument is malformed (`ArgumentError`) the caller keeps it; on any later failure, a deadline included, the
  stream is closed.

### Handshake timeouts

`handshake_timeout` (a positive finite number of seconds, in `connect_tls`, `tls.connect` and `tls.accept`) bounds
the TLS handshake only: expiry raises `core.DeadlineExceededError` and closes the stream. In `connect_tls` the TCP
connect is not covered: bound it with `reactor.deadline`.

| Entry point | Default |
|---|---|
| `tls.connect`, `connect_tls` | 10 seconds (implemented) |
| `tls.accept` | **60 seconds, decided, not implemented**: it is 10 seconds today (OQ-47 (2), owner, 2026-10-27) |

Both defaults are editable per call through `handshake_timeout`.

### TlsStream

Implements `Stream`.

- `read` returns `nil` after the peer's `close_notify` (a clean end) and raises `TlsError` when the transport ends
  without it (`reason = "truncated"`), so a truncation is never taken for a clean end (RFC 8446 section 6.1).
- `write` encrypts all of `data` or raises; concurrent writes run one after the other, each intact.
- `shutdown()` *suspends*: sends `close_notify` and half-closes the transport; idempotent. A write after it raises
  `TransportError` (`EPIPE`). `close()` never suspends and **cannot** send `close_notify`: call `shutdown()` first.
- `handshake()` is called by the entry points. Also `alpn()`, `requested_server_name()` (the SNI a client sent;
  `nil` on client streams), `version()` (`"TLSv1.3"` or `"TLSv1.2"`), `peer_certificate()` (DER of the verified
  end-entity certificate), `peer_address()`, `local_address()` and `set_nodelay(bool)` (forwarded to the inner
  stream, which must provide them), `reader()`, `writer()`, `is_closed()`.
- A closed stream raises `TransportError` (`EBADF`).

### Revocation of client certificates

**Decided, not implemented** (owner, 2026-10-27, OQ-47 (6)): a CRL option on the server configuration, to check
client certificates for revocation. **Limit until then:** the server configures no CRLs, so a revoked client
certificate that chains to `client_ca_pem` is accepted. Revocation of server certificates is the operating
system's business and depends on the platform (see "Trust").

## Error classes

All are `hecate.core` errors with a stable `code` (the full class name); messages follow
[coding-standards.md](coding-standards.md#errors): the qualified name of the call the caller wrote, a lower-case
first word, the offending value and the expected one.

| Class | Raised when |
|---|---|
| `reactor.TransportError` (a `core.NetworkError`; also `net.TransportError`, the same class) | TCP, UDP, pipe and resolution failures, and use after close. `context.errno` is the libuv name (`ECONNREFUSED`, `EPIPE`, `EADDRINUSE`, `EAI_NONAME`, ...), `context.operation` the operation. `EBADF` after close; `ECANCELED` when the object was closed while a coroutine waited on it. `IoError` is **not** raised by `net` (OQ-32 (5)). |
| `net.EndOfStreamError` (a `NetworkError`) | The stream ended inside a read; `context.buffered` bytes stay in the reader. |
| `net.TlsError` (a `NetworkError`) | A failed handshake or verification, a protocol failure, a truncation, or the native module not built. `context.reason`: `untrusted_issuer`, `name_mismatch`, `expired`, `not_yet_valid`, `revoked`, `alpn_mismatch`, `truncated`, `transport_ended`, `stalled`, `native_missing`. It is absent when the kind is not recognised: the operating system's verifiers report many failures as text only. |
| `core.NetworkError` | A call on a poisoned `BufferedWriter` (`cause` is the first failure). |
| `core.ProtocolError` | A line or record beyond its limit, or a `read_exact` count beyond its `limit`. |
| `core.ArgumentError` | A malformed host, port, option or argument; checked before anything is resolved or sent. |
| `core.DeadlineExceededError` | A handshake beyond `handshake_timeout`, or a `reactor.deadline` the caller set. |
| `core.NonYieldableContextError` | A suspending call outside a managed coroutine. |
| `core.Error` | A second coroutine reads, accepts or receives at once on the same object. |

`TransportError` and `IoError` are siblings (`core` has no multiple inheritance): a transport failure is not an
`IoError`. A failure of the `reactor` layer is renamed to the net call (`reactor.connect_pipe: ...` becomes
`net.connect_pipe: ...`), keeping its class, `errno` and `operation`.

## Cancellation rules

There is no `timeout` argument on any operation. A deadline or cancellation comes from the caller:
`reactor.deadline(seconds, fn, ...)`, a scope, or `reactor.cancel`. Cancellation is level-triggered
([concurrency.md](concurrency.md)). What each cancelled operation leaves behind:

| Operation | After cancellation |
|---|---|
| `connect`, `connect_pipe` (not yet completed) | The handle is closed; with several addresses, no further address is tried. |
| `resolve` | The caller is released at once; the late answer is discarded. |
| `TcpStream:read`, `PipeStream:read`, `TlsStream:read` | The stream stays open; no data is lost. Exception: a cancellation that interrupts the sending of ciphertext the TLS session queued (key update, alert) closes the stream like a cancelled write. |
| `write` on `TcpStream`, `PipeStream` | The stream is closed (the bytes sent are unknown). |
| `TlsStream:write` | Closes the stream and the inner stream when the session had accepted bytes; a write cancelled while waiting its turn changes nothing. |
| `shutdown` (TCP, pipe, TLS) | Closes the stream. |
| `accept` (`TcpListener`, `PipeListener`) | The listener stays open and the queued connections are kept. |
| `UdpSocket:receive_from` | The socket stays open; no datagram is lost. |
| `UdpSocket:send_to` | The socket is closed. |
| `BufferedReader` reads | A cancelled read leaves what was received in the buffer; the reader is intact. |
| `BufferedWriter:flush`, `write` that flushes, direct write | The writer is poisoned. |
| TLS handshake | The stream is closed. |
| `close` (every class) | Never suspends, so never cancelled; wakes the coroutines waiting on the object with `ECANCELED`. |

```lua
local stream <close> = reactor.deadline(5, net.connect, "example.org", 80) -- resolution and connect
local reader = stream:reader()
local ok, err = pcall(reactor.deadline, 2, function() return reader:read_line() end)
-- On DeadlineExceededError the read was withdrawn: the stream and the reader are intact.
```

## Defaults and limits

| Item | Value | Where |
|---|---|---|
| `nodelay` | `true` | TCP |
| `keepalive`, `keepalive_delay` | `false`, 60 s | TCP |
| `backlog` | 128 | TCP, pipes |
| `BufferedReader` `limit` | 65536 bytes | per line or record |
| Reader chunk | 16 KiB | `BufferedReader` |
| `BufferedWriter` `capacity` | 8192 bytes (to be benchmarked, see above) | |
| TCP read-ahead | 64 KiB | `TcpStream` |
| Handshake timeout | 10 s; 60 s for `tls.accept` is decided, not implemented | TLS |
| `alpn` protocol | 1 to 255 bytes | TLS |
| Cached default client configurations | 16 | `connect_tls` |
| Unix socket path | 107 bytes (103 on macOS) | `sun_path` |
| Windows pipe name | 256 characters | |
| `max_message` | 16 MiB, editable per peer | `reactor.ipc`, not `net` |
| Resolver threads | 4 (libuv default) | `getaddrinfo` |

## Decided, not yet implemented

The `net` follow-up of the [roadmap](../roadmap.md) (owner decisions of 2026-10-27, OQ-47):

1. `net.listen` binds every resolved address (supersedes OQ-32 (3)).
2. A Unix socket is created inside a `0700` directory, or equivalent, instead of binding then calling `chmod`.
3. A CRL option for client certificates; the limit is documented above until then.
4. Handshake defaults split: 10 s for `tls.connect` and `connect_tls`, 60 s for `tls.accept`, both editable.
5. A benchmark of the `BufferedWriter` capacity against Go's 4 KiB `bufio` and other frameworks, which decides the
   default.
6. `BufferedWriter:close` flushing under `reactor.shield` (OQ-23; needs the `reactor` follow-up).

Not decided and not planned: see "Non-goals".

## Testing guidance

- Unit tests use in-memory streams for the buffered layer and wrap `reactor.resolve` and `reactor.connect_tcp` to
  script multi-address connects; restore them in every path.
- Integration tests run on loopback (TCP, UDP, pipes) and, for TLS, against a local test CA
  (`packages/net/tests/fixtures`, throwaway certificates). Hermetic TLS tests use `system_roots = false`; one test
  per platform covers the default path, and one reaches a public server where `HECATE_NETWORK_TESTS=1`.
- TLS tests fail, not skip, when `HECATE_REQUIRE_TLS=1` and the native module is missing.
- Tests pin `family = "inet"` or use numeric addresses, because `listen("localhost", ...)` binds one address today.
- Order events with futures and joins, not `reactor.sleep`.
- Fault injection: resets, half-close, slow peers, truncation without `close_notify`.
- Every example in `packages/net/examples/` is run by a test.
- Benchmarks: `read-until`, `buffered-writer`, `tls-throughput` (`lua tools/run.lua bench net`) and the network
  scenario `tcp-echo` (10 000 connections).

## Open points

- OQ-47 (8): the `reuseport` branch of TCP cannot run in CI until luv supports it (OQ-43).
- Shape of `TcpListener` once it binds several addresses (local address, one handle per address): to be written
  with the implementation of follow-up item 1.
- Form of the CRL option (file, PEM string, list) and its refresh: to be decided with follow-up item 3; record it
  in `docs/open-questions.md` when the work starts.
- Session resumption, OCSP stapling policy, SNI-based certificate selection on the server, peer certificate
  details beyond the DER: not done (OQ-41).
- Datagram truncation and loss: not specified or tested (OQ-42 (8)).
