# 0023 — Multi-process serving: share-nothing workers behind a listening-strategy abstraction

- **Status:** Accepted
- **Date:** 2026-10-18
- **Deciders:** project owner (agreed 2026-10-18)
- **Packages:** reactor, kernel, cli (and the benchmarks, CI and Docker tooling)
- **Related:** [concurrency.md](../architecture/concurrency.md) ("Workers"), [spike OQ-8](../spikes/OQ-8-multi-process.md), ADR 0002, ADR 0003, ADR 0021, OQ-1, OQ-8, OQ-27, OQ-43

## Context

Hecate serves requests from one Lua state per process, and gets its parallelism from
**several processes** (concurrency.md, "Model"), not from threads. Multi-process serving is
therefore part of the design from the start, not an add-on, and it must be fast on Linux, the
platform where most Hecate servers will run. macOS and Windows must work and be correct, but they
must never set the design of the Linux path.

The specification first outlined the approach (workers bind with `SO_REUSEPORT` on Linux; on macOS
and Windows the primary owns the listening socket and shares it through libuv IPC handle passing)
and left its validation to OQ-8. The spike ([report](../spikes/OQ-8-multi-process.md)) measured it
on the three platforms, with four workers:

| Strategy | Linux | macOS | Windows |
|---|---|---|---|
| each worker binds with `SO_REUSEPORT` | evenly: largest to smallest worker 1.09 to 1.13, the fastest | **one worker took every connection** | not available |
| one listening socket shared by all workers | badly unbalanced (94 to 278) | unbalanced (4.3 to 4.9) | **one worker took every connection** |
| the primary accepts and passes each connection to the next worker | perfect (1.00), about two thirds of the `SO_REUSEPORT` throughput | perfect (1.00) | perfect (1.00), slower (about 3300 connections per second) |

What follows from the measurements:

- `SO_REUSEPORT` is the right strategy on Linux and only there: the kernel balances, and nothing
  stands between the kernel and the workers.
- A shared listening socket balances nowhere. The assumption that Windows would distribute
  connections over a shared socket was wrong, so the strategy is dropped.
- Passing each accepted connection from the primary balances everywhere and works on all three
  platforms with no native code. It costs throughput, because the primary is in the path, which is
  acceptable off Linux and is exactly why Linux must not use it.
- luv 1.53 exposes `reuseport` for UDP but **not for TCP** (`tcp_bind` knows only `ipv6only`),
  although the bundled libuv has `UV_TCP_REUSEPORT`. A four-line patch (in the report) makes
  `tcp:bind(host, port, { reuseport = true })` work; it behaves like the native module the spike
  used first (OQ-43).

## Options considered

1. **One strategy everywhere** (always pass connections from the primary). Consequences: simple,
   but Linux pays an extra hop and a third of its throughput for nothing. Rejected: it lets the
   weakest platform set the design.
2. **A shared listening socket where `SO_REUSEPORT` does not balance** (macOS, Windows).
   Consequences: no primary in the data path in principle, but measured unbalanced or not
   distributing at all. Rejected.
3. **Threads with several Lua states in one process** (`offload`-style). Consequences: shared
   file descriptors would be easy, but every cross-state message needs serialisation, the standard
   library and native modules must be thread-safe, and OQ-27 already scoped threads to pure
   functions. Rejected for request serving.
4. **Share-nothing worker processes with a listening strategy chosen per platform, behind one
   interface.** Consequences: the application code is identical everywhere, Linux keeps the
   kernel-balanced path with no primary in it, and the other platforms get a balanced path through
   the primary. Two strategies, covered by one conformance suite. **Chosen.**

## Decision

1. **Workers are processes, and nothing is shared.** `hecate serve --workers N` (default
   `uv.available_parallelism()`, the number of CPU cores) starts a **primary** and N **workers**.
   A worker is the same program started again with a worker role: it has its own Lua state, its own
   reactor and its own connections. State shared between workers lives outside the processes
   (database, Redis); Hecate offers no shared memory.
2. **Mechanism in `reactor`, policy in `kernel`.**
   - `hecate.reactor` gains the platform-isolated primitives and nothing else (the Phase 2 reactor
     follow-up of OQ-27):
     - `reactor.spawn(program, args, options)`: a long-lived child as a `Process` (`:wait()`,
       `:kill(signal)`, `pid`), with environment and standard stream inheritance, unlike
       `run_process`, which runs a child to completion.
     - `reactor.ipc`: a framed message channel between a parent and its child, with optional
       handle passing. `Peer:send(message, handle?)` and `Peer:receive() → message, handle?`
       (a `TcpStream` can be passed); a child reaches its parent with `reactor.ipc.parent()`.
       Messages are strings: serialising them is the caller's concern (`reactor` stays below
       `json`).
     - `reactor.tcp_listen(host, port, { reuseport = true })`.
   - `hecate.kernel` owns the policy: the **supervisor** in the primary (start, readiness, restart
     with exponential backoff and a crash-loop limit, signals, rolling reload, graceful shutdown)
     and the **listening strategies**.
3. **A listening strategy is the only platform-dependent part.** It is an interface with four
   operations: `supported() → boolean, reason` (can this platform run it), `prepare(endpoint)`
   (in the primary, once), `worker_listener(context) → Listener` (in the worker: where the worker
   accepts connections from), and `run(workers)` (in the primary: the dispatch loop, empty for a
   strategy that needs none). Everything above the `Listener` (server, router, handlers) is
   identical for every strategy. Two implementations:

   | Strategy | Who accepts | Primary in the data path | Platform |
   |---|---|---|---|
   | `reuseport` | each worker, on its own socket bound with `SO_REUSEPORT` | no | Linux (default) |
   | `round_robin` | the primary, which passes every accepted connection to the next worker | yes (accept and pass only) | macOS and Windows (default), and the fallback everywhere |

   `server.workers.strategy` is `auto` (the platform default above) or a strategy name. When the
   chosen strategy is not `supported()`, the server falls back to `round_robin`, which works
   everywhere, and logs a warning that names the reason.
4. **Linux first, enforced.** The platform-specific code lives in the strategies and in the
   `reactor` primitives, behind capability queries, never in the common path. The `reuseport` path
   has no IPC in the data path and no dispatch loop. A change to a common abstraction needs the
   Linux benchmark of the verification section not to regress.
5. **The control channel is the same on every platform and is not in the data path.** Each worker
   has an IPC channel to the primary. It carries `ready`, `stop(deadline)`, `reload` and counters.
   A worker that sees the channel close (the primary died) drains and exits, which gives
   orphan protection without `PR_SET_PDEATHSIG`. The primary never signals workers directly: it
   sends `stop`, then kills the process after the deadline, which behaves the same on Windows where
   POSIX signals do not exist.
6. **Graceful shutdown and reload per strategy.** A stopping worker closes its listener, drains the
   requests in flight until the deadline, then cancels what remains (concurrency.md, "Signals and
   shutdown"). With `round_robin` the primary stops dispatching to a draining worker, so nothing is
   lost. With `reuseport` the connections queued in the closing socket's backlog are reset by the
   kernel; a rolling reload therefore starts the replacement worker, waits for its `ready`, then
   stops the old one, and keeps at most one worker out of service at a time. This limit is
   documented, not hidden.
7. **Prerequisite on Linux: TCP `SO_REUSEPORT` from Lua.** Needed by the `reuseport` strategy and
   absent from luv 1.53 (OQ-43 lists the options). Until it is settled, `auto` selects
   `round_robin` on Linux too, so the framework works but is not yet at its intended speed there.

Out of scope: threads (`offload`, OQ-27), session affinity (sticky connections, WebSocket
pinning: a worker cannot hand a live connection to another), and zero-downtime binary upgrades by
file-descriptor inheritance across a new binary.

## Consequences

- `kernel` gets a supervisor and two strategies; `reactor` gets `spawn`, `ipc` and the `reuseport`
  option. The roadmap item "worker-process primitives" (Phase 2) is specified by this ADR, and
  `kernel` depends on it.
- A conformance suite runs against every supported strategy on the three platforms: every
  connection is served, the spread of connections stays within a bound for the balanced
  strategies, a crashed worker is restarted, and shutdown honours its deadline.
- Linux keeps the shortest possible path; macOS and Windows get a correct and balanced one that
  can be tuned without touching Linux. On Windows the primary's hand-off is the slowest part
  (about 3300 connections per second in the spike); batching or another mechanism can be studied
  there later without affecting the other platforms.
- Long-lived connections stay on the worker that took them: the spread of *connections* is
  balanced, the spread of *load* is not guaranteed. Documented in the operations guide.

## Verification

- A benchmark scenario (`benchmarks/`, Phase 1) records connections per second and the spread
  (largest to smallest worker) for each strategy on each platform; the Linux `reuseport` result is
  the reference that common changes must not degrade.
- CI runs the conformance suite on Linux, macOS and Windows.
- `check-boundaries` keeps `reactor` free of policy: strategies and supervision are in `kernel`.
