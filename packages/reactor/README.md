# `hecate-reactor`

> The reactor over libuv (luv): coroutine scheduler, futures, structured concurrency, synchronisation primitives, timers, signals, processes, file system.

| | |
|---|---|
| Module | `hecate.reactor` |
| Rock | `hecate-reactor` |
| Layer | 1 — Runtime |
| Roadmap phase | 1 |
| Status | in progress — scheduler, `Future`, `fork`/`join`/`select`/`sleep`/`scope`/`deadline`, cancellation and virtual clock, `Channel`, `Semaphore`, `Mutex`, `Monitor` and `Condition` implemented; `detach`, signals, processes, file system and TCP transport implemented; `offload` and worker primitives pending |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core) |
| Used by | `cli`, `hecate`, `http`, `kernel`, `log`, `mongodb`, `mysql`, `net`, `orm`, `postgresql`, `redis`, `sql`, `sqlite`, `sqlserver`, `test`, `websocket` |
| Native code | luv (libuv binding) |
| Specification | [concurrency.md](../../docs/architecture/concurrency.md) |
| Decisions | [ADR 0002](../../docs/adr/0002-libuv-via-luv.md), [ADR 0003](../../docs/adr/0003-transparent-structured-concurrency.md), [ADR 0004](../../docs/adr/0004-academic-vocabulary.md) |
| Agent | [`pkg-reactor`](../../.claude/agents/pkg-reactor.md) |
| Repository | read-only mirror `hecate-framework/hecate-reactor`, generated from this directory (ADR 0017) |

## Responsibilities

- scheduler resuming coroutines on libuv completions
- `fork`, `join`, `select`, `deadline`, `sleep`, `scope`, `detach`
- `Future`, `Channel`, `Semaphore`, `Mutex`, `Monitor`, `Condition`
- cooperative cancellation (`CancellationError`) and `DeadlineExceededError`
- timers, signals, child processes, pipes, file-system operations and TCP transport (connect, listen, accept, read, write, shutdown) as suspending calls; UDP, DNS and pipes follow
- virtual clock for tests

## Non-goals

- network protocols (see `net`)
- OS threads running Lua code
- `offload` and worker process primitives (OQ-8): Phase 2 follow-up (OQ-27)

## Standards and references

- Schmidt, *Reactor* (1995)
- Hoare, *CSP* (1978)
- structured concurrency (Sústrik 2016; Smith 2018)

## Public API

Implemented (steps 1 to 4, then TCP transport). Every function marked *suspends* is `---@async` and raises
`NonYieldableContextError` outside a managed coroutine or inside a non-yieldable C boundary.

| Name | Description |
|---|---|
| `reactor.run(fn, ...)` | Runs `fn` on a new real-clock reactor until it and everything it forked have finished. |
| `reactor.Reactor({ clock = "real"\|"virtual", start = 0 })` | The scheduler; `:run(fn, ...)`, `:now()`, `:live_tasks()`. The virtual clock jumps to the next timer when nothing is ready (deterministic tests). |
| `reactor.fork(fn, ...)` | Managed coroutines only (raises otherwise). Starts `fn` in the current scope, returns a `Future`. |
| `reactor.join(f1, ...)` | *suspends*. Values in argument order; the first failure cancels the others and is raised. |
| `reactor.select(f1, ...)` | *suspends*. Returns `index, value` of the first future to finish; cancels the others. |
| `reactor.sleep(seconds)` | *suspends*. `0` yields to the other ready coroutines. |
| `reactor.scope(fn)` | *suspends*. Runs `fn(scope)`; returns only after every child has completed or been cancelled; raises the first failure. |
| `reactor.deadline(seconds_or_instant, fn, ...)` | *suspends*. Cancels `fn` and raises `DeadlineExceededError` when late. |
| `reactor.now()`, `reactor.at(seconds)` | Reading of the running clock; absolute `Instant` for `deadline` (OQ-22). |
| `reactor.detach(fn, ...)` | *suspends*. Starts `fn` in the application scope; its failure is seen only through its future (OQ-26). |
| `reactor.fs` | *suspend*: `read_file(path)`, `write_file(path, data)`, `stat(path)` (nil if absent), `remove`, `mkdir`, `rmdir`, `list(path)`. Real clock only; failures raise `reactor.IoError` (`context.errno`). |
| `reactor.wait_signal(name, ...)` | *suspends*. Returns the name of the first signal delivered (`"sigint"`, `"sigterm"`, ...). |
| `reactor.run_process(program, args)` | *suspends*. Runs a program, returns `{ code, signal, stdout, stderr }`; the child is killed on cancellation. |
| `reactor.tcp_connect(host, port, options?)` | *suspends*. Connects to a numeric address (no name resolution, OQ-30); returns a `TcpStream`. Bound it with `deadline`; cancellation abandons the attempt and closes its handle. Options: `nodelay` (default `true`), `keepalive` (default `false`), `keepalive_delay` (seconds, default 60). |
| `reactor.tcp_listen(host, port, options?)` | Binds and listens (port 0 picks a free port); returns a `TcpListener`. Options as above plus `backlog` (default 128); accepted streams inherit `nodelay` and `keepalive`. |
| `TcpStream` | `:read(max?)` (*suspends*) returns at most `max` bytes, nil at end of stream, never an empty string; cancelling keeps the stream open and loses no data. `:write(data)` (*suspends*) returns once the bytes were handed to the system (back-pressure); a cancelled write closes the stream. `:shutdown()` (*suspends*) half-closes; `:close()` is idempotent and never suspends, `local s <close> = ...` closes on scope exit; `:is_closed()`, `:peer_address()`, `:local_address()` (`{ ip, port, family }`), `:set_nodelay(bool)`, `:set_keepalive(bool, delay?)`. Failures raise `IoError` (`context.errno`: libuv name; `EBADF` after close, `ECANCELED` when closed while waiting). |
| `TcpListener` | `:accept()` (*suspends*) returns a `TcpStream`; cancelling keeps the listener and queued connections. `:close()`, `:is_closed()`, `:local_address()`; `<close>`-able. |
| `Future` | `:value()` (*suspends*), `:cancel()`, `:done()`, `:state()` (`pending`, `completed`, `failed`, `cancelled`). |
| `Scope` | `:fork(fn, ...)`, `:cancel()`, `:is_cancelled()`, `:live()`. |
| `reactor.Channel(capacity)` | `:send(v)`, `:receive()` (*suspend*), `:close()`, `:is_closed()`, `:length()`, `:capacity()`; capacity 0 is a rendezvous channel. Receivers drain the buffer of a closed channel, then `ClosedChannelError` is raised; sends on a closed channel raise it too. `:receive_op()` and `:send_op(v)` build operations for `select`. |
| `reactor.Semaphore(n)` | `:acquire()` (*suspends*) returns a `Permit`; `:try_acquire()`, `:release()` (adds a unit), `:available()`, `:waiting()`. FIFO, no barging. |
| `reactor.Mutex()` | `:lock()` (*suspends*) returns a `Permit`; `:try_lock()`, `:is_locked()`, `:waiting()`. |
| `reactor.Monitor()`, `reactor.Condition` | `monitor:enter()` (*suspends*) returns a `Permit`; `monitor:condition()` creates a `Condition`; `condition:wait()` (*suspends*), `:signal()`, `:broadcast()`, `:waiting()`. Mesa semantics: test the predicate in a loop (OQ-25). |
| `Permit` | `:release()` (idempotent), `:is_held()`; closing it releases it: `local permit <close> = mutex:lock()`. |

Cancellation is cooperative and level-triggered: it is raised as a `CancellationError` at
every suspension point of a cancelled scope (OQ-23); a failing child cancels its siblings and the
scope raises the first failure (OQ-24). Requires `luv` (tests need it on `LUA_CPATH`).

## Layout (once implemented)

```text
src/hecate/reactor/init.lua   public entry point (reactor, future, scope, instant, primitives)
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
csrc/        native sources
```
