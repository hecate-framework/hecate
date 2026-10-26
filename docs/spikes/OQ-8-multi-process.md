# OQ-8: multi-process serving, how connections spread over workers

Owner direction (2026-10-18): Hecate is multi-process by design, through an abstraction that
serves each platform in the best possible way, and Linux, where most servers will run, is never
compromised for the sake of another platform. This spike measures the candidate listening
strategies on the three platforms. The design it supports is
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

## Follow-up: a fair comparison on Linux (2026-10-18)

The first measurement ran its load generator inside the primary, so the primary and the generator
shared one core, and it only used one-line connections that close at once. That handicapped the
strategy in which the primary hands connections off, and it said nothing about keep-alive traffic,
which is what HTTP servers mostly see. [`OQ-8/bench.lua`](OQ-8/bench.lua) fixes both: the load
generator is a separate process (2 workers, the primary and the generator on the four cores), and
it runs two loads for 8 seconds with 64 clients: **churn** (a new connection per request) and
**keep-alive** (persistent connections, one request after another). One run per cell after a
warm-up, indicative; the generator (a single Lua process) is the first limit in every cell.

| Load | Strategy | Requests per second | Spread (largest to smallest) | CPU of the primary |
|---|---|---|---|---|
| churn | `reuseport` | 10800 to 11200 | 1.00 to 1.02 | none (not in the path) |
| churn | primary hands off | 10000 to 12200 | 1.00 | 3.0 s of 8 s (37% of a core) |
| keep-alive | `reuseport` | 73000 to 80400 | 1.06 to 1.17 | none |
| keep-alive | primary hands off | 73400 to 80300 | 1.01 to 1.03 | 0.0 s (idle) |

- **For keep-alive traffic the two strategies are the same speed**, and the hand-off balances
  better (1.01 to 1.03 against 1.06 to 1.17 for the kernel's hash), because after the accept the
  primary is not involved at all.
- **For churn they are the same speed at this rate too.** The cost of the hand-off is visible only
  in the primary's CPU: about 37% of a core at 10 000 new connections per second, that is about 37
  microseconds of primary time per connection. A single primary therefore tops out near 27 000 new
  connections per second on this hardware; beyond that `reuseport` (each worker accepts) scales and
  the hand-off does not.
- The "two thirds of the throughput" of the first table was an artefact of the generator sharing
  the primary's core. It is withdrawn.

## What Node and luvit do (read on 2026-10-18)

- Node's `cluster` module offers two policies: round-robin, where the primary accepts and hands
  connections to the workers (`SCHED_RR`), and a shared listening handle (`SCHED_NONE`). Round-robin
  is the default on every platform except Windows. The documentation gives our own finding as the
  reason: the shared handle "should, in theory, give the best performance. In practice however,
  distribution tends to be very unbalanced due to operating system scheduler vagaries. Loads have
  been observed where over 70% of all connections ended up in just two processes, out of a total
  of eight." On Windows Node still defaults to the shared handle, "until libuv is able to
  effectively distribute IOCP handles" ([cluster documentation](https://nodejs.org/api/cluster.html)).
  Our Windows run agrees with that caveat (every connection to one worker), which is why ADR 0023
  chooses the hand-off on Windows too.
- Node added a TCP `SO_REUSEPORT` option on top of libuv's flag in October 2024 (pull request
  nodejs/node#55408, "net: add UV_TCP_REUSEPORT for tcp", the same week as the UDP one, #55403). The
  exact shape of the option and its first version were not confirmed here.
- luvit has no cluster or multi-process server module (its repository has a `bench/http-cluster`
  benchmark directory and nothing else matching `cluster`, `fork` or `reuseport`).

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
   throughput only for new connections, because the primary is in the path: nothing for keep-alive
   traffic, about 37 microseconds of primary time per new connection on Linux (see the follow-up),
   and the slowest result on Windows (about 3300 connections per second in the first measurement,
   where each hand-off duplicates the socket).
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
everywhere. `reuseport` is an optimisation for a very high rate of new connections (above about
25 000 per second per host), not a requirement: the framework is complete and as fast for keep-alive
traffic with `round_robin` alone, so OQ-43 does not block anything.

The temporary CI workflow that produced the macOS and Windows figures is removed; the spike
script stays here so that the figures can be reproduced (`lua spike.lua <mode> [workers]
[connections]`, with `luv` installed in `.hecate/rocks` and `rp.c` built next to the script for
`reuseport`).
