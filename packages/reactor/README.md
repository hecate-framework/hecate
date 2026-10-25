# `hecate-reactor`

> The reactor over libuv (luv): coroutine scheduler, futures, structured concurrency, synchronisation primitives, timers, signals, processes, file system.

| | |
|---|---|
| Module | `hecate.reactor` |
| Rock | `hecate-reactor` |
| Layer | 1 — Runtime |
| Roadmap phase | 1 |
| Status | in progress — scheduler, `Future`, `fork`/`join`/`select`/`sleep`/`scope`/`deadline`, cancellation and virtual clock, `Channel`, `Semaphore`, `Mutex`, `Monitor` and `Condition` implemented; `detach`, ambient context, signals, processes, file system, TCP, UDP and pipe transport and `resolve` implemented; `spawn`, `ipc` (framed messages with handle passing, over a message pipe) and the TCP `reuseport` option implemented (ADR 0023; effective only with a luv that supports it, OQ-43); `offload` pending |
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
- timers, signals, child processes, pipes, file-system operations and TCP transport (connect, listen, accept, read, write, shutdown) as suspending calls; TCP, UDP (`udp_bind`) and pipes (`pipe_connect`, `pipe_listen`) transport, and name resolution (`resolve`), all as suspending calls
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
| `reactor.Reactor({ clock = "real"\|"virtual", start = 0 })` | The scheduler; `:run(fn, ...)`, `:now()`, `:live_coroutines()`. The virtual clock jumps to the next timer when nothing is ready (deterministic tests). |
| `reactor.fork(fn, ...)` | Managed coroutines only (raises otherwise). Starts `fn` in the current scope, returns a `Future`. |
| `reactor.join(f1, ...)` | *suspends*. Values in argument order; the first failure cancels the others and is raised. |
| `reactor.select(f1, ...)` | *suspends*. Returns `index, value` of the first future to finish; cancels the others. |
| `reactor.sleep(seconds)` | *suspends*. `0` yields to the other ready coroutines. |
| `reactor.scope(fn)` | *suspends*. Runs `fn(scope)`; returns only after every child has completed or been cancelled; raises the first failure. |
| `reactor.deadline(seconds_or_instant, fn, ...)` | *suspends*. Cancels `fn` and raises `DeadlineExceededError` when late. |
| `reactor.now()`, `reactor.at(seconds)` | Reading of the running clock; absolute `Instant` for `deadline` (OQ-22). |
| `reactor.detach(fn, ...)` | *suspends*. Starts `fn` in the application scope; its failure is seen only through its future (OQ-26). |
| `reactor.with_ambient(key, value, fn, ...)`, `reactor.ambient(key)` | Ambient context (ADR 0025): immutable bindings visible in `fn` and in computations forked or detached from it; `ambient` is also `reactor.ambient`. Managed coroutines only. |
| `reactor.fs` | *suspend*: `read_file(path)`, `write_file(path, data)`, `stat(path)` (nil if absent), `remove`, `mkdir`, `rmdir`, `list(path)`. Real clock only; failures raise `reactor.IoError` (`context.errno`). |
| `reactor.wait_signal(name, ...)` | *suspends*. Returns the name of the first signal delivered (`"sigint"`, `"sigterm"`, ...). |
| `reactor.run_process(program, args)` | *suspends*. Runs a program, returns `{ code, signal, stdout, stderr }`; the child is terminated on cancellation. It inherits this process's environment without the marker of its own message pipe, and does not inherit that pipe. On Windows a child ended by `kill` reports `code` 1 and `signal` 0: detect a crash by `code` there. |
| `reactor.spawn(program, args?, options?)` | Starts a long-lived child and returns a `Process` at once (`.pid`, `.ipc`, `:wait()` *suspends*, `:kill(signal?)`, `:is_running()`). Options: `env` (added to the inherited environment; names are case-insensitive on Windows), `cwd`, `ipc` (message pipe), `stdout`/`stderr` (`"inherit"` default or `"ignore"`). The caller waits for or kills the child and closes `process.ipc`. Only a child started with `ipc = true` holds the message pipe: a process it starts in turn gets neither the pipe nor the environment marker. A running child keeps the libuv loop alive (waiting for it with nothing else pending is no deadlock); `reactor.run` returns when its main coroutine ends, running child or not. `kill` is a signal operation, not the cancellation mechanism (`reactor.scope`, `reactor.deadline`): it treats an already vanished child (`ESRCH`) as success and raises `IoError` for an invalid signal. **Windows:** only `SIGTERM`, `SIGKILL`, `SIGINT` and `0` are supported (others fail with `ENOSYS`), a killed child reports `code` 1 and `signal` 0, a program is looked up in the working directory first and then in `PATH`, `.cmd` and `.bat` scripts cannot be started directly (run `cmd.exe /c`), and `"inherit"` needs a valid standard output and error in this process (a service without them: pass `"ignore"`). |
| `reactor.ipc` | Framed message pipe between parent and child (ADR 0023). `process.ipc` is the parent's `Peer`, `reactor.ipc.parent(options?)` the child's (nil when started without `ipc`; the same peer on every call; the environment marker is removed once the pipe is open). `Peer:send(message, stream?)` (*suspends*) sends a string of at most `max_message` bytes (default 16 MiB) and optionally hands a `TcpStream` over (closed in the sender afterwards); `Peer:receive()` (*suspends*) returns `message, stream?`, nil when the other end closed; `:close()`, `:is_closed()`. `reactor.Peer(handle, { max_message })` and `ipc.parent({ max_message })` set the size limit, applied to what is sent and received. A cancelled receive keeps the peer open and loses nothing; a malformed frame, or a stream that arrives without or against its announcement, raises `TransportError` `EPROTO` and closes the peer; a pipe that ends inside a frame raises `EPIPE`; a closed peer raises `EBADF` (`ECANCELED` for a coroutine waiting while it closes). Messages are strings: serialising them is the caller's concern. **Windows:** the stream is duplicated for the receiver and the duplicate is valid only while the sender's socket is open, and the sender closes it when `send` returns: have the receiver acknowledge with a message before the sender exits. |
| `reactor.supports_reuseport()` | Whether `tcp_listen(..., { reuseport = true })` works here (probed once). Needs luv with TCP `reuseport` (OQ-43); otherwise `tcp_listen` raises `TransportError` `ENOTSUP` rather than ignoring the option. Says nothing about balance: macOS accepts the flag and does not balance. |
| `reactor.resolve(host, options?)` | *suspends*. Resolves a host name or numeric address to `{ ip, family }` entries in the resolver's order (option `family`: `"inet"` or `"inet6"`). Failure raises `TransportError` (`errno` such as `EAI_NONAME`); cancellation releases the caller at once and discards the late result (OQ-32). |
| `reactor.tcp_connect(host, port, options?)` | *suspends*. Connects to a numeric address (no name resolution, OQ-30); returns a `TcpStream`. Bound it with `deadline`; cancellation abandons the attempt and closes its handle. Options: `nodelay` (default `true`), `keepalive` (default `false`), `keepalive_delay` (a positive integer number of seconds, default 60). |
| `reactor.tcp_listen(host, port, options?)` | Binds and listens (port 0 picks a free port); returns a `TcpListener`. Options as above plus `backlog` (default 128); accepted streams inherit `nodelay` and `keepalive`. |
| `TcpStream` | `:read(max?)` (*suspends*) returns at most `max` bytes, nil at end of stream, never an empty string; cancelling keeps the stream open and loses no data. `:write(data)` (*suspends*) returns once the bytes were handed to the system (back-pressure); a cancelled write closes the stream. `:shutdown()` (*suspends*) half-closes; `:close()` is idempotent and never suspends, `local s <close> = ...` closes on scope exit; `:is_closed()`, `:peer_address()`, `:local_address()` (`{ ip, port, family }`), `:set_nodelay(bool)`, `:set_keepalive(bool, delay?)`. Failures raise `TransportError` (a `core.NetworkError`) (`context.errno`: libuv name; `EBADF` after close, `ECANCELED` when closed while waiting). Once read, the stream reads ahead of its reader by up to 64 KiB, then stops reading from the socket until the reader caught up (back-pressure). |
| `TcpListener` | `:accept()` (*suspends*) returns a `TcpStream`; cancelling keeps the listener and queued connections; a connection whose peer already reset it (`EINVAL`, `ENOTCONN`, `ECONNRESET` while applying the options, seen on BSD and macOS) is closed and skipped. `:close()`, `:is_closed()`, `:local_address()`; `<close>`-able. Connections are not guaranteed to be accepted in arrival order (libuv on Windows hands pending ones out last-in first-out). |
| `reactor.pipe_connect(path)`, `reactor.pipe_listen(path, options?)` | `pipe_connect` *suspends*. Unix-domain sockets (named pipes on Windows); `PipeStream` and `PipeListener` behave like their TCP counterparts (`:path()` too). `pipe_listen` options: `backlog` (positive integer, default 128, ignored on Windows) and `mode`: `"owner"` (default, the socket file is restricted to its owner), `"readable"`, `"writable"` or `"readwrite"` (open to every user with that access); `mode` has no effect on Windows. The path must not exist (`EADDRINUSE`); the socket path is limited to 107 bytes (103 on macOS), a Windows pipe name to 256 characters. |
| `Future` | `:value()` (*suspends*), `:cancel()`, `:done()`, `:state()` (`pending`, `completed`, `failed`, `cancelled`). |
| `Scope` | `:fork(fn, ...)`, `:cancel()`, `:is_cancelled()`, `:live()`. |
| `reactor.Channel(capacity)` | `:send(v)`, `:receive()` (*suspend*), `:close()`, `:is_closed()`, `:length()`, `:capacity()`; capacity 0 is a rendezvous channel. Receivers drain the buffer of a closed channel, then `ClosedChannelError` is raised; sends on a closed channel raise it too. `:receive_op()` and `:send_op(v)` build operations for `select`. |
| `reactor.Semaphore(n)` | `:acquire()` (*suspends*) returns a `Permit`; `:try_acquire()`, `:release()` (adds a unit), `:available()`, `:waiting()`. FIFO, no barging. |
| `reactor.Mutex()` | `:lock()` (*suspends*) returns a `Permit`; `:try_lock()`, `:is_locked()`, `:waiting()`. |
| `reactor.Monitor()`, `reactor.Condition` | `monitor:enter()` (*suspends*) returns a `Permit`; `monitor:condition()` creates a `Condition`; `condition:wait()` (*suspends*), `:signal()`, `:broadcast()`, `:waiting()`. Mesa semantics: test the predicate in a loop (OQ-25). |
| `Permit` | `:release()` (idempotent), `:is_held()`; closing it releases it: `local permit <close> = mutex:lock()`. |

Terms: the framed parent/child connection of `spawn` is a *message pipe* (not a channel: `reactor.Channel` is the in-process rendezvous of coroutines).

Cancellation is cooperative and level-triggered: it is raised as a `CancellationError` at
every suspension point of a cancelled scope (OQ-23); a failing child cancels its siblings and the
scope raises the first failure (OQ-24). Requires `luv` (tests need it on `LUA_CPATH`).

## Layout

```text
src/hecate/reactor/init.lua   public entry point (reactor, future, scope, instant, primitives)
src/hecate/reactor/internal/  scheduler context, libuv call helpers, environment merge
tests/unit/  tests/integration/  tests/fixtures/
examples/                     tested examples of the reference
```

Micro-benchmark: `benchmarks/scheduler.lua` (fork and join, channel ping-pong, concurrent timers; `lua tools/run.lua bench reactor`). The `tcp-echo` scenario of the repository-level harness measures the reactor under 10 000 connections. There are no native sources of our own yet (luv is the only native code).
