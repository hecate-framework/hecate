# 0027 — `kernel` depends on `net` for the listening strategies

- **Status:** Accepted
- **Date:** 2026-11-11
- **Deciders:** project owner (accepted 2026-11-11)
- **Packages:** kernel, net
- **Related:** [ADR 0023](0023-multi-process-serving.md), [concurrency.md](../architecture/concurrency.md) ("Workers"), [overview.md](../architecture/overview.md)

## Context

ADR 0023 puts the listening strategies in `kernel`: `prepare(endpoint)` binds the listening socket in the primary
(`round_robin`), `worker_listener(context)` returns the listener a worker accepts from (`reuseport` binds its own
socket), and `run(workers)` passes each accepted connection to a worker. The listener a worker returns is served by
`hecate.http.Server:serve(listener)`, which expects a `net` listener: its `accept` returns a stream with `reader`,
`writer`, `shutdown` and `close` (`hecate.net.TcpStream`).

A connection handed over through `reactor.ipc` arrives as a `hecate.reactor.TcpStream` (the `reactor` layer knows
nothing of `net`), and `Peer:send` takes a `reactor` stream. Something must therefore bind `net` listeners in the
primary and in a `reuseport` worker, unwrap a `net` stream before the hand-over and wrap the received `reactor` stream
into a `net.TcpStream` in the worker. The declared dependencies of `kernel` (its rockspec and `packages/kernel/CLAUDE.md`)
do not include `net`, and that file asks for an ADR for any other dependency. `net` is layer 1, `kernel` layer 3:
the edge goes downward and creates no cycle (`http` already depends on `net`).

## Options considered

1. **`kernel` depends on `net`.** The strategies call `net.listen` (with `reuseport` for that strategy) and wrap a
   received stream with `net.TcpStream`. Consequences: one more declared edge, downward; the strategies use the same
   listener type as `http.Server:listen`.
2. **`http` exposes the wrapping** (for example `http.Server:serve` accepting a listener of `reactor` streams).
   Consequences: no new edge for `kernel`, but `http` gains a transport concern that belongs to `net`, and the
   primary of `round_robin` still needs a listener that `kernel` cannot bind without `net` or `reactor` directly.
3. **`kernel` uses `reactor.listen_tcp` and writes its own buffered stream.** Consequences: duplicates the buffered
   reader and writer of `net`, which the "one framework" rule forbids.

## Decision

`hecate-kernel` declares `hecate-net` as a dependency (rockspec, `packages/kernel/CLAUDE.md`, README). Only the
listening strategies use it: `net.listen` to bind, `net.TcpStream` to wrap a stream received from the primary, and the
`net.TcpStream:transport()` to get the inner `reactor` stream of a `net.TcpStream` and hand it over.

`net` offers that accessor as public API (owner decision, 2026-11-11): `TcpStream:transport()` returns the `hecate.reactor` stream under the buffered one. It is meant for the hand-over of a freshly accepted connection: bytes that a reader of the `net` stream already buffered are not in the transport.

## Consequences

- `check-boundaries` accepts `require("hecate.net")` in `kernel`.
- Reading the inner `reactor` stream of a `net.TcpStream` is done in one place of `kernel` (the `round_robin`
  strategy), through the public `TcpStream:transport()`, never through a private field.

## Verification

- `check-boundaries` and `check-rockspecs` pass with the new edge.
- The unit tests of `hecate.kernel.listening` exercise both directions (unwrap before the hand-over, wrap after it).
