---
description: The design of multi-process serving in hecate (ADR 0023): share-nothing workers, a primary, two listening strategies and a message pipe, and which parts exist today.
hecate: "0.x"
lua: "5.5"
order: 3
---

# Multi-process serving

This page explains how hecate uses several processes to serve requests, and why. It is
written for hecate 0.x and Lua 5.5. The design is ADR 0023 (accepted 2026-10-18).

> [!NOTE] What exists today
> The primitives in `hecate.reactor` (`reactor.spawn`, `reactor.ipc`) and the policy in
> `hecate.kernel` exist: the supervisor, the `round_robin` strategy, the keys `server.workers`
> and `server.strategy`, graceful shutdown and the rolling reload. Two parts are missing. The
> `reuseport` strategy is written but waits for luv support (OQ-43). There is no `hecate serve
> --workers` command yet: an `Application` starts its workers itself. The section
> [What exists today](#what-exists-today) lists every piece.

## Why processes

A hecate process runs one Lua state and one [reactor](../reference/glossary.md#concurrency). Its
coroutines share that state and run one at a time. To use several CPU cores, hecate runs several
processes, not several threads in one process. Threads would need a Lua state each, every message
between them would need serialisation, and every native module would have to be thread-safe.

Multi-process serving is part of the design from the start. It must be fast on Linux, where most
servers will run. macOS and Windows must work and be correct, but they never decide the design of
the Linux path.

## Share-nothing workers

A server is one [primary](../reference/glossary.md#concurrency) and *N*
[workers](../reference/glossary.md#concurrency). A worker is the same program started again with
a worker role. It has its own Lua state, its own reactor and its own connections. The default for
*N* is the number of CPU cores.

Nothing is shared between workers. State that must be shared lives outside the processes, in a
database or in Redis. hecate offers no shared memory.

The primary starts the workers, waits until each says it is ready, restarts one that crashes, and
shuts them down. A connection stays on the worker that took it. This keeps the number of
*connections* balanced, but not the amount of *load*: a worker with several long-lived connections
can be busier than the others.

## Mechanism and policy

The work is split in two packages.

- `hecate.reactor` has the mechanism, the platform-specific primitives: `reactor.spawn`,
  `reactor.ipc` and the `reuseport` option. They know nothing about servers.
- `hecate.kernel` has the policy: the supervisor in the primary (start, readiness,
  restart with exponential backoff and a crash-loop limit, signals, rolling reload, graceful
  shutdown) and the listening strategies.

## Listening strategies

A [listening strategy](../reference/glossary.md#concurrency) decides where a worker obtains its
connections. It is the only part of the design that depends on the platform. Everything above it,
the server, the router and the actions, is the same for every strategy. There are two.

| Strategy | Who accepts | Primary in the data path | Default on |
|---|---|---|---|
| `reuseport` | each worker, on its own socket bound with `SO_REUSEPORT` | no | Linux |
| `round_robin` | the primary, which hands each accepted connection to the next worker | yes, for accepting and handing over only | macOS and Windows, and the fallback everywhere |

`server.strategy` is `auto`, which picks the platform default, or the name of a
strategy. When the chosen strategy is not supported, the server falls back to `round_robin`,
which works everywhere, and logs a warning with the reason.

### Why these two

The design rests on a measurement on the three platforms, with four workers.

- **`reuseport`** balanced evenly on Linux. On macOS one worker took every
  connection. It does not exist on Windows. It is the right choice on Linux and nowhere else.
- **One listening socket shared by all workers** balanced badly on Linux and macOS, and on Windows
  one worker took every connection. It balances nowhere, so it is not offered.
- **The primary accepts and hands each connection over** balanced perfectly on all three platforms,
  with no native code. For long-lived connections and up to about 10,000 new connections per
  second it was as fast as `reuseport`. (A first measurement showed a gap on Linux. It came from a load
  generator that shared the primary's core, and it disappeared when the generator ran in its own
  process.) The primary spends about 37 microseconds per new
  connection, which puts the ceiling near 27,000 per second on the test host. On Windows the
  hand-over is slower, about 3,300 connections per second.

So `round_robin` is the default where `reuseport` does not balance, and the fallback. `reuseport` only
matters on Linux, for a server that opens more than about 10,000 new connections per second, which
a server that reuses connections does not.

## The message pipe

Each worker has a [message pipe](../reference/glossary.md#concurrency)
to the primary, the same on every platform and never in the data path. It carries `ready` and
`stop(deadline)` today. The name `reload` is reserved, and the counters are not
implemented yet.

- A worker that sees the pipe close knows that the primary died. It drains and exits. No
  platform-specific orphan protection is needed.
- The primary never signals a worker directly. It sends `stop`, and kills the process after the
  deadline. That behaves the same on Windows, where POSIX signals do not exist.
- With `round_robin`, the same pipe carries the connections: `Peer:send` hands a `TcpStream` to a
  worker, together with a message.

## Shutdown and reload

A stopping worker closes its listener, finishes the requests in flight until the
deadline, then cancels what remains.

- With `round_robin` the primary stops handing connections to a draining worker, so nothing is lost.
- With `reuseport`, the kernel resets the connections queued in the backlog of a socket that
  closes. A rolling reload therefore starts the replacement worker, waits for its `ready`, then
  stops the old one, and keeps at most one worker out of service at a time. This limit is
  documented, not hidden.

The rolling reload exists in `kernel` (`Supervisor:reload`; `SIGHUP` in the primary, or
`Application:reload`, which takes one options table, `{ grace_timeout?, ready_timeout? }`). It replaces the workers by restart, one at a time, and sends no `reload`
message: that name stays reserved.

Workers inherit the whole environment of the primary, plus the `HECATE_WORKER_*` variables of their
role. A worker refuses a malformed host or backlog in those variables.

## What exists today

| Piece | Status |
|---|---|
| `reactor.spawn`, `Process` (`wait`, `kill`, `pid`) | Implemented. |
| `reactor.ipc`: `Peer:send`, `Peer:receive`, handle passing, `ipc.parent()` | Implemented. |
| TCP `reuseport` option, `reactor.supports_reuseport()` | Implemented, but see below. |
| Supervisor: readiness, restart, graceful shutdown, rolling reload (`kernel`) | Implemented. |
| Strategy `round_robin`, configuration keys `server.workers` and `server.strategy` | Implemented. |
| Strategy `reuseport` | Written, waits for luv support (see below). |
| `hecate serve --workers` | Not implemented (the `cli` package, Phase 3). |
| Control-protocol counters | Not implemented. |
| Conformance suite of the strategies on three platforms | Not implemented. |

### `reuseport` does not work yet

The TCP `reuseport` option needs a version of luv that exposes it for TCP. luv 1.53, the version
hecate is pinned to, does not (OQ-43). `reactor.supports_reuseport()` returns `false`, and
`listen_tcp(..., { reuseport = true })` raises `TransportError` with `ENOTSUP`, instead of
ignoring the option. Until luv supports it, `auto` selects `round_robin` on Linux too. The
framework stays complete, and as fast for connections that are reused.

Where the option is supported, it says nothing about balance: macOS accepts the flag and does not
balance.

To assemble a hand-made version with these primitives, follow
[Run child processes and pass connections between processes](../how-to/run-processes-and-pass-connections.md).
You then write the supervision yourself.

## Limits

- A worker ignores `sigterm` and `sigint`, because a terminal sends them to the whole process
  group. `kill <worker pid>` does nothing: only the primary stops a worker.
- Windows never delivers `sigterm` and does not watch `sighup`. A service manager that stops the
  primary with `TerminateProcess` gets no graceful shutdown. The workers see the message pipe
  close and drain with the default grace period.
- On Linux, `SO_REUSEPORT` lets any process of the same user bind the same port and take a share of
  the connections. On a shared host, `round_robin` is the safer choice.

## Out of scope

Threads for request serving, session affinity (a worker cannot hand a live connection to another
worker, so WebSocket connections stay where they started), and zero-downtime binary upgrades by
inheriting descriptors across a new binary.

## See also

- [Run child processes and pass connections between processes](../how-to/run-processes-and-pass-connections.md)
- [The transport model](transport-model.md)
- Reference: [`reactor.spawn`](../reference/reactor/functions/spawn.md),
  [`reactor.ipc`](../reference/reactor/ipc.md),
  [`reactor.supports_reuseport`](../reference/reactor/functions/supports_reuseport.md),
  [`reactor.listen_tcp`](../reference/reactor/functions/listen_tcp.md)
