# 0023 — Multi-process serving: share-nothing workers behind a listening-strategy abstraction

- **Status:** Proposed
- **Date:** 2026-10-18
- **Deciders:** project owner (to promote)
- **Packages:** reactor, kernel, cli (and the benchmarks, CI and Docker tooling)
- **Related:** [concurrency.md](../architecture/concurrency.md) ("Workers"), [spike OQ-8](../spikes/OQ-8-multi-process.md), ADR 0002, ADR 0003, ADR 0021, OQ-1, OQ-8, OQ-27, OQ-43

## Context

Hecate serves requests from one Lua state per process, and gets its parallelism from
**several processes** (concurrency.md, "Model"), not from threads. Multi-process serving is
therefore part of the design from the start, not an add-on, and it must be fast on Linux, the
platform where most Hecate servers will run. macOS and Windows must work and be correct, but they
must never set the design of the Linux path.

The specification already outlines the approach: workers bind with `SO_REUSEPORT` on Linux, and on
macOS and Windows the primary owns the listening socket and shares it through libuv IPC handle
passing (OQ-8). The spike ([report](../spikes/OQ-8-multi-process.md)) measured what that means:

- On Linux, four workers that each bind the port with `SO_REUSEPORT` share the connections evenly
  (largest to smallest worker 1.05 to 1.13) and give the best throughput. Nothing sits between the
  kernel and the workers.
- A listening socket **shared** between the workers is badly unbalanced on Linux (one worker took
  almost every connection; largest to smallest 50 to 260). It cannot be the Linux strategy.
- A primary that accepts and hands each connection to the next worker balances perfectly
  (1.00), at about two thirds of the `SO_REUSEPORT` throughput in the spike, because the primary is
  in the data path.
- luv 1.53 exposes `reuseport` for UDP but **not for TCP** (`tcp_bind` knows only `ipv6only`),
  although the bundled libuv has `UV_TCP_REUSEPORT`. A four-line patch (in the report) makes
  `tcp:bind(host, port, { reuseport = true })` work; it behaves like the native module the spike
  used first.
- libuv documents that `SO_REUSEPORT` does not balance on macOS and the BSDs (the last binder
  takes the traffic) and does not exist on Windows. The macOS and Windows figures come from CI
  ([report](../spikes/OQ-8-multi-process.md)), not from the cloud session.

## Options considered

1. **One strategy everywhere** (always round-robin through the primary, or always a shared socket).
   Consequences: simple, but either Linux pays an extra hop it does not need, or Linux gets the
   unbalanced shared socket. Rejected: it lets the weakest platform set the design.
2. **Threads with several Lua states in one process** (`offload`-style). Consequences: shared
   file descriptors would be easy, but every cross-state message needs serialisation, the standard
   library and native modules must be thread-safe, and OQ-27 already scoped threads to pure
   functions. Rejected for request serving.
3. **Share-nothing worker processes with a listening strategy chosen per platform, behind one
   interface.** Consequences: the application code is identical everywhere, Linux keeps the
   kernel-balanced path with no primary in it, and the platforms that need the primary get it. More
   code (three strategies), covered by one conformance suite. **Chosen.**

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
       (a `TcpStream` or a `TcpListener` can be passed); a child reaches its parent with
       `reactor.ipc.parent()`. Messages are strings: serialising them is the caller's concern
       (`reactor` stays below `json`).
     - `reactor.tcp_listen(host, port, { reuseport = true })`, and a listener built from a passed
       handle.
   - `hecate.kernel` owns the policy: the **supervisor** in the primary (start, readiness, restart
     with exponential backoff and a crash-loop limit, signals, rolling reload, graceful shutdown)
     and the **listening strategies**.
3. **A listening strategy is the only platform-dependent part.** It is an interface with four
   operations: `supported() → boolean, reason` (can this platform run it), `prepare(endpoint)`
   (in the primary, once: bind the shared socket, if any), `worker_listener(context) → Listener`
   (in the worker: where the worker accepts connections from), and `run(workers)` (in the primary:
   the dispatch loop, empty for strategies that need none). Everything above the `Listener`
   (server, router, handlers) is identical for every strategy. Three implementations:

   | Strategy | Who accepts | Primary in the data path | Intended platform |
   |---|---|---|---|
   | `reuseport` | each worker, on its own socket bound with `SO_REUSEPORT` | no | Linux (default) |
   | `shared_socket` | each worker, on one listening socket passed by the primary | no | Windows (proposed default) |
   | `round_robin` | the primary, which passes every accepted connection to the next worker | yes (accept and pass only) | macOS (proposed default) |

   `server.workers.strategy` is `auto` (the platform default above), or a strategy name. When the
   chosen strategy is not `supported()`, the server falls back to `round_robin`, which works
   everywhere, and logs a warning that names the reason.
4. **Linux first, enforced.** The platform-specific code lives in the strategies and in the
   `reactor` primitives, behind capability queries, never in the common path. The `reuseport` path
   has no IPC in the data path and no dispatch loop. A change to a common abstraction needs the
   Linux benchmark of the next point not to regress.
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
   stops the old one, and keeps at most one worker out of service at a time. This limit is documented, not hidden.
7. **Prerequisite on Linux: TCP `SO_REUSEPORT` from Lua.** Needed by the `reuseport` strategy and
   absent from luv 1.53 (see OQ-43 for the options). Until it is settled, `auto` selects
   `round_robin` on Linux, so the framework works but is not yet at its intended speed there.

Out of scope: threads (`offload`, OQ-27), session affinity (sticky connections, WebSocket
pinning: a worker cannot hand a live connection to another), and zero-downtime binary upgrades by
file-descriptor inheritance across a new binary.

## Consequences

- `kernel` gets a supervisor and three strategies; `reactor` gets `spawn`, `ipc` and the
  `reuseport` option. The roadmap item "worker-process primitives" (Phase 2) is specified by this
  ADR, and `kernel` depends on it.
- A conformance suite runs against every supported strategy on the three platforms: every
  connection is served, the spread of connections stays within a bound for the balanced
  strategies, a crashed worker is restarted, and shutdown honours its deadline.
- Linux keeps the shortest possible path; macOS and Windows get a correct one that can be tuned
  without touching Linux.
- Long-lived connections stay on the worker that took them: the spread of *connections* is
  balanced, the spread of *load* is not guaranteed. Documented in the operations guide.

## Verification

- A benchmark scenario (`benchmarks/`, Phase 1) records connections per second and the spread
  (largest to smallest worker) for each strategy on each platform; the Linux `reuseport` result is
  the reference that common changes must not degrade.
- CI runs the conformance suite on Linux, macOS and Windows, and the temporary spike workflow until
  the suite replaces it.
- `check-boundaries` keeps `reactor` free of policy: strategies and supervision are in `kernel`.
