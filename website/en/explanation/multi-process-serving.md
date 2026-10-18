---
description: The design of multi-process serving in hecate (ADR 0023): share-nothing workers, a primary, two listening strategies and a message pipe, and which parts exist today.
hecate: "0.x"
lua: "5.5"
order: 3
---

# Multi-process serving

This page explains how hecate will use several processes to serve requests, and why. It is
written for hecate 0.x and Lua 5.5. The design is ADR 0023 (accepted 2026-10-18).

::: warning What exists today
Only the **primitives** in `hecate.reactor` exist: `reactor.spawn`, `reactor.ipc` and the
`reuseport` option of TCP listeners. The `kernel` package, which holds the supervisor and the
listening strategies, is not implemented yet. There is no `hecate serve --workers` command today.
Sections marked *Planned* describe the design, not the current behaviour. The section
[What exists today](#what-exists-today) lists both.
:::

## Why processes

A hecate process runs one Lua state and one [reactor](../reference/glossary.md#concurrency). Its
coroutines share that state and run one at a time. To use several CPU cores, hecate runs several
processes, not several threads in one process. Threads would need a Lua state each, every message
between them would need serialisation, and every native module would have to be thread-safe.

Multi-process serving is part of the design from the start. It must be fast on Linux, where most
servers will run. macOS and Windows must work and be correct, but they never decide the design of
the Linux path.

## Share-nothing workers

*Planned.* A server is one [primary](../reference/glossary.md#concurrency) and *N*
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
- `hecate.kernel` will have the policy: the supervisor in the primary (start, readiness,
  restart with exponential backoff and a crash-loop limit, signals, rolling reload, graceful
  shutdown) and the listening strategies.

## Listening strategies

A [listening strategy](../reference/glossary.md#concurrency) decides where a worker obtains its
connections. It is the only part of the design that depends on the platform. Everything above it,
the server, the router and the handlers, is the same for every strategy. There are two.

| Strategy | Who accepts | Primary in the data path | Default on |
|---|---|---|---|
| `reuseport` | each worker, on its own socket bound with `SO_REUSEPORT` | no | Linux |
| `round_robin` | the primary, which hands each accepted connection to the next worker | yes, for accepting and handing over only | macOS and Windows, and the fallback everywhere |

`server.workers.strategy` will be `auto`, which picks the platform default, or the name of a
strategy. When the chosen strategy is not supported, the server falls back to `round_robin`,
which works everywhere, and logs a warning with the reason.

### Why these two

The design rests on a measurement on the three platforms, with four workers.

- **`reuseport`** balanced evenly on Linux, and was the fastest. On macOS one worker took every
  connection. It does not exist on Windows. It is the right choice on Linux and nowhere else.
- **One listening socket shared by all workers** balanced badly on Linux and macOS, and on Windows
  one worker took every connection. It balances nowhere, so it is not offered.
- **The primary accepts and hands each connection over** balanced perfectly on all three platforms,
  with no native code. For long-lived connections and up to about 10,000 new connections per
  second it was as fast as `reuseport`. The primary spends about 37 microseconds per new
  connection, which puts the ceiling near 27,000 per second on the test host. On Windows the
  hand-over is slower, about 3,300 connections per second.

So `round_robin` is the default where `reuseport` does not balance, and the fallback. `reuseport` only
matters on Linux, for a server that opens more than about 10,000 new connections per second, which
a server that reuses connections does not.

## The message pipe

*Planned use; the primitive exists.* Each worker has a [message pipe](../reference/glossary.md#concurrency)
to the primary, the same on every platform and never in the data path. It carries `ready`,
`stop(deadline)`, `reload` and counters.

- A worker that sees the pipe close knows that the primary died. It drains and exits. No
  platform-specific orphan protection is needed.
- The primary never signals a worker directly. It sends `stop`, and kills the process after the
  deadline. That behaves the same on Windows, where POSIX signals do not exist.
- With `round_robin`, the same pipe carries the connections: `Peer:send` hands a `TcpStream` to a
  worker, together with a message.

## Shutdown and reload

*Planned.* A stopping worker closes its listener, finishes the requests in flight until the
deadline, then cancels what remains.

- With `round_robin` the primary stops handing connections to a draining worker, so nothing is lost.
- With `reuseport`, the kernel resets the connections queued in the backlog of a socket that
  closes. A rolling reload therefore starts the replacement worker, waits for its `ready`, then
  stops the old one, and keeps at most one worker out of service at a time. This limit is
  documented, not hidden.

## What exists today

| Piece | Status |
|---|---|
| `reactor.spawn`, `Process` (`wait`, `kill`, `pid`) | Implemented. |
| `reactor.ipc`: `Peer:send`, `Peer:receive`, handle passing, `ipc.parent()` | Implemented. |
| TCP `reuseport` option, `reactor.supports_reuseport()` | Implemented, but see below. |
| Supervisor: readiness, restart, graceful shutdown, rolling reload (`kernel`) | Not implemented. |
| Strategies `reuseport` and `round_robin`, `server.workers.strategy` | Not implemented. |
| `hecate serve --workers` | Not implemented. |
| Conformance suite of the strategies on three platforms | Not implemented. |

### `reuseport` does not work yet

The TCP `reuseport` option needs a version of luv that exposes it for TCP. luv 1.53, the version
hecate is pinned to, does not (OQ-43). `reactor.supports_reuseport()` returns `false`, and
`tcp_listen(..., { reuseport = true })` raises `TransportError` with `ENOTSUP`, instead of
ignoring the option. Until luv supports it, `auto` will select `round_robin` on Linux too. The
framework stays complete, and as fast for connections that are reused.

Where the option is supported, it says nothing about balance: macOS accepts the flag and does not
balance. Check `supports_reuseport()` before you use it:

```lua
if reactor.supports_reuseport() then
  -- every worker binds the same port itself
  listener = reactor.tcp_listen("0.0.0.0", 8080, { reuseport = true })
else
  -- the primary accepts and passes each connection to a worker
end
```

This is the building block that the `reuseport` strategy will wrap. Without the option, a second
process that binds the same port fails to bind.

### Building your own workers today

You can already assemble a hand-made version with the primitives. Start workers with
`reactor.spawn(..., { ipc = true })`, accept in the parent, and pass each connection with
`peer:send(message, stream)`. The guide
[Run child processes and pass connections between processes](../how-to/run-processes-and-pass-connections.md)
shows each step. You must then write the supervision yourself: readiness, restarts and shutdown.

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
  [`reactor.tcp_listen`](../reference/reactor/functions/tcp_listen.md)
