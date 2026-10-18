# OQ-8: multi-process serving, how connections spread over workers

Owner direction (2026-10-18): Hecate is multi-process by design, through an abstraction that
serves each platform in the best possible way, and Linux, where most servers will run, is never
compromised for the sake of another platform. This spike measures the candidate listening
strategies on the three platforms. The design it supports is the Proposed
[ADR 0023](../adr/0023-multi-process-serving.md).

## What was measured

[`OQ-8/spike.lua`](OQ-8/spike.lua) starts a primary and N worker processes (each a separate Lua
state with its own libuv loop) and opens 4000 connections from the primary, 100 at a time. Every
accepted connection receives the worker's number, so the load generator can count how many
connections each worker took. The *spread* is the largest count divided by the smallest over all
workers, a worker that took nothing included (infinite): 1.00 is perfect.

| Mode | Who accepts |
|---|---|
| `reuseport` | each worker binds the port with `SO_REUSEPORT` (descriptor from the small C module [`rp.c`](OQ-8/rp.c), handed to `tcp:open`) |
| `reuseport_luv` | the same through `tcp:bind(host, port, { reuseport = true })` on a patched luv ([patch](OQ-8/luv-tcp-reuseport.patch)); Linux only, run once locally |
| `shared` | one listening socket, bound by the primary, passed to every worker (libuv IPC handle passing) |
| `round_robin` | the primary accepts and passes each connection to the next worker |

Limits of the measurement: one load generator that shares the machine (and, for `shared` and
`round_robin`, the process) with the primary; loopback; short connections that send one line;
four workers on the four-core hosted runners; two runs per mode. The figures compare strategies
with each other, they are not benchmark results (the benchmark harness is a Phase 1 item).

## Results

GitHub-hosted runners, four workers, 4000 connections, two runs each (the C module was built on
the runner for `reuseport`):

| Platform | Strategy | Connections per worker | Workers used | Spread | Connections per second |
|---|---|---|---|---|---|
| Linux | `reuseport` | 944 / 1020 / 1009 / 1027 and 983 / 953 / 1025 / 1039 | 4 of 4 | 1.09 | 12700 to 13100 |
| Linux | `shared` | 25 / 138 / 1345 / 2492 and 3569 / 38 / 81 / 312 | 4 of 4 | 94 to 278 | 10400 to 11200 |
| Linux | `round_robin` | 1000 each | 4 of 4 | 1.00 | 8600 to 10100 |
| macOS (arm64) | `reuseport` | 0 / 0 / 0 / 4000 (both runs) | **1 of 4** | infinite | 45000 to 49000 (one worker) |
| macOS (arm64) | `shared` | 484 / 2075 / 647 / 794 and 441 / 518 / 871 / 2170 | 4 of 4 | 4.3 to 4.9 | 39600 to 41400 |
| macOS (arm64) | `round_robin` | 1000 each | 4 of 4 | 1.00 | 24200 to 25700 |
| Windows | `shared` | 0 / 0 / 0 / 4000 (both runs) | **1 of 4** | infinite | 3750 |
| Windows | `round_robin` | 1000 each | 4 of 4 | 1.00 | 3300 |

The first local runs in the cloud session (Ubuntu 24.04, four cores) agree: `reuseport` 1.05 to
1.13, `shared` 43 to 261, `round_robin` 1.00, and `reuseport_luv` (patched luv) 1.05 to 1.08.

## Findings that shape the design

1. **`SO_REUSEPORT` balances on Linux only.** On macOS it gives the whole load to one worker
   (the last binder takes the traffic, as the libuv documentation says) and it does not exist on
   Windows. It is the fastest strategy on Linux because nothing stands between the kernel and the
   workers.
2. **A listening socket shared by all workers balances nowhere**: unbalanced on Linux and macOS,
   and on Windows it did not distribute at all in this setup (every connection to one worker).
   It is dropped.
3. **Passing each accepted connection from the primary balances perfectly on all three platforms**
   and needs no native code: libuv handle passing works for an accepted TCP connection
   (`pipe:write2`, `pipe:pending_count`, `pipe:accept`; the IPC pipe is the child's fourth
   standard stream, `stdio = { nil, 1, 2, ipc }` and `pipe:open(3)` in the child). Its cost is
   throughput, because the primary is in the path: about two thirds of the `reuseport` figure on
   Linux, and the slowest result on Windows (about 3300 connections per second, where each
   hand-off duplicates the socket).
4. **luv cannot set `SO_REUSEPORT` on a TCP socket.** luv 1.53 reads `reuseport` for UDP only;
   `tcp_bind` reads `ipv6only` and nothing else (checked in `src/tcp.c` of luv master of
   2026-09-30), although the bundled libuv defines `UV_TCP_REUSEPORT`. Passing the flag as an
   integer is ignored. Two ways to get it, both verified here: the four-line luv patch
   ([`luv-tcp-reuseport.patch`](OQ-8/luv-tcp-reuseport.patch), built and run against Lua 5.5) or a
   small native module that creates the socket (`rp.c`). Both gave the same spread. Decision for
   the owner: OQ-43.
5. The first version of the spike hid finding 1: its spread ignored a worker that took nothing and
   read "1.00" for macOS `reuseport`. The metric now counts every worker.

## Recommendation

ADR 0023: share-nothing workers; mechanism in `reactor` (`spawn`, `ipc` with handle passing, TCP
`reuseport`), policy in `kernel` (supervisor, two listening strategies). `auto` selects
`reuseport` on Linux and `round_robin` on macOS and Windows, with `round_robin` as the fallback
everywhere. For Linux speed now, settle OQ-43 (until then `round_robin` serves Linux too).

The temporary CI workflow that produced the macOS and Windows figures is removed; the spike
script stays here so that the figures can be reproduced (`lua spike.lua <mode> [workers]
[connections]`, with `luv` installed in `.hecate/rocks` and `rp.c` built next to the script for
`reuseport`).
