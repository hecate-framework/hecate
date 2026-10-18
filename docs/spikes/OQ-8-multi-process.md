# OQ-8: multi-process serving, how connections spread over workers

Owner direction (2026-10-18): Hecate is multi-process by design, through an abstraction that
serves each platform in the best possible way, and Linux, where most servers will run, is never
compromised for the sake of another platform. This spike measures the candidate listening
strategies. The design it supports is the Proposed [ADR 0023](../adr/0023-multi-process-serving.md).

## What was measured

[`OQ-8/spike.lua`](OQ-8/spike.lua) starts a primary and N worker processes (each a separate Lua
state with its own libuv loop) and opens 4000 connections from the primary, 100 at a time. Every
accepted connection receives the worker's number, so the load generator can count how many
connections each worker took. The *spread* is the largest count divided by the smallest: 1.00 is
perfect.

| Mode | Who accepts |
|---|---|
| `reuseport` | each worker binds the port with `SO_REUSEPORT` (descriptor from the small C module [`rp.c`](OQ-8/rp.c), handed to `tcp:open`) |
| `reuseport_luv` | the same through `tcp:bind(host, port, { reuseport = true })` on a patched luv ([patch](OQ-8/luv-tcp-reuseport.patch)) |
| `shared` | one listening socket, bound by the primary, passed to every worker (libuv IPC handle passing) |
| `round_robin` | the primary accepts and passes each connection to the next worker |

Limits of the measurement: one load generator that shares the machine (and, for `shared` and
`round_robin`, the process) with the primary; loopback; short connections that send one line.
The figures compare strategies with each other, they are not benchmark results (the benchmark
harness is a Phase 1 item).

## Linux (cloud session, Ubuntu 24.04, 4 cores, 4 workers)

| Strategy | Connections per worker | Spread | Connections per second |
|---|---|---|---|
| `reuseport` (C module) | 1896 / 2138 / 1981 / 1985 (8000) | 1.13 | 9700 to 11600 |
| `reuseport_luv` (patched luv) | 1902 / 2017 / 2042 / 2039 (8000) | 1.07 | 7900 to 11300 |
| `shared` | 65 / 173 / 706 / 7056 (8000) | 108 | 7300 |
| `round_robin` | 2000 / 2000 / 2000 / 2000 (8000) | 1.00 | 7900 |

Repeated runs gave the same picture (`reuseport` 1.05 to 1.13, `shared` 50 to 260 depending on the
run, `round_robin` always 1.00).

- `SO_REUSEPORT` balances and is the fastest: nothing stands between the kernel and the workers.
- A shared listening socket is not a Linux strategy: the workers wake together and whichever runs
  first takes the connection, so one worker takes almost everything.
- `round_robin` balances perfectly and costs throughput, because the primary accepts every
  connection and sends a message to the worker.

## Findings that shape the design

1. **luv cannot set `SO_REUSEPORT` on a TCP socket.** luv 1.53 reads `reuseport` for UDP only;
   `tcp_bind` reads `ipv6only` and nothing else (checked in `src/tcp.c` of luv master of
   2026-09-30), although the bundled libuv defines `UV_TCP_REUSEPORT`. Passing the flag as an
   integer is ignored. Two ways to get it, both verified here: the four-line luv patch
   ([`luv-tcp-reuseport.patch`](OQ-8/luv-tcp-reuseport.patch), built and run against Lua 5.5), or a
   small native module that creates the socket (`rp.c`). Both gave the same spread. Decision for
   the owner: OQ-43.
2. **Without `SO_REUSEPORT`, Linux is slower or unbalanced**, so the framework must not make
   `round_robin` or `shared` the default there.
3. **Handle passing works for both a listening socket and an accepted connection** in luv
   (`pipe:write2`, `pipe:pending_count`, `pipe:accept`), so `shared_socket` and `round_robin` need
   no native code. The IPC pipe is the child's fourth standard stream (`stdio = { nil, 1, 2, ipc }`
   and `pipe:open(3)` in the child).
4. libuv documents that `SO_REUSEPORT` does not balance on macOS and the BSDs and does not exist
   on Windows, so a strategy that does not depend on it is needed there.

## macOS and Windows (GitHub Actions)

The temporary workflow `.github/workflows/spike-oq8.yml` runs the spike on the three platforms
when `docs/spikes/OQ-8/` changes: `reuseport` (Linux and macOS), `shared` and `round_robin` (all).
Figures: see the section below once the runs are in.

## Recommendation

ADR 0023: share-nothing workers; mechanism in `reactor` (`spawn`, `ipc` with handle passing, TCP
`reuseport`), policy in `kernel` (supervisor, listening strategies). `auto` selects `reuseport` on
Linux, `round_robin` on macOS and `shared_socket` on Windows (the last two to be confirmed by the
figures above), with `round_robin` as the fallback everywhere. For Linux speed now, settle OQ-43.
