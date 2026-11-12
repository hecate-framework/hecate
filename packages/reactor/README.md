# `hecate-reactor`

> The reactor over libuv (luv): coroutine scheduler, futures, structured concurrency, synchronisation primitives, timers, signals, processes, file system, network transport (TCP, UDP, pipes, name resolution), ambient context, `offload` of Lua functions to the libuv thread pool.

| | |
|---|---|
| Module | `hecate.reactor` |
| Rock | `hecate-reactor` |
| Layer | 1 — Runtime |
| Roadmap phase | 1 (the transport primitives of ADR 0023: phase 2) |
| Status | alpha — scheduler, `Future`, `fork`/`join`/`select`/`sleep`/`scope`/`deadline`, cancellation and virtual clock, `Channel`, `Semaphore`, `Mutex`, `Monitor` and `Condition` implemented; `detach`, ambient context, signals (`wait_signal`, persistent `SignalWatcher`), processes, file system, TCP, UDP and pipe transport and `resolve` implemented; `spawn`, `ipc` (framed messages with handle passing, over a message pipe) and the TCP `reuseport` option implemented (ADR 0023; effective only with a luv that supports it, OQ-43); `offload` implemented (OQ-27, choices to confirm in OQ-119) |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core) |
| Used by | `cli`, `hecate`, `http`, `kernel`, `log`, `mongodb`, `mysql`, `net`, `orm`, `postgresql`, `redis`, `sql`, `sqlite`, `sqlserver`, `test`, `websocket` |
| Native code | luv (libuv binding) |
| Specification | [concurrency.md](../../docs/architecture/concurrency.md) |
| Decisions | [ADR 0002](../../docs/adr/0002-libuv-via-luv.md), [ADR 0003](../../docs/adr/0003-transparent-structured-concurrency.md), [ADR 0004](../../docs/adr/0004-academic-vocabulary.md), [ADR 0023](../../docs/adr/0023-multi-process-serving.md), [ADR 0025](../../docs/adr/0025-ambient-context.md) |
| Agent | [`pkg-reactor`](../../.claude/agents/pkg-reactor.md) |
| Repository | read-only mirror `hecate-framework/hecate-reactor`, generated from this directory (ADR 0017) |

## Responsibilities

- scheduler resuming coroutines on libuv completions
- `fork`, `join`, `select`, `deadline`, `sleep`, `scope`, `detach`
- `Future`, `Channel`, `Semaphore`, `Mutex`, `Monitor`, `Condition`
- cooperative cancellation (`CancellationError`) and `DeadlineExceededError`
- `offload`: self-contained Lua functions run on the libuv thread pool, values copied between Lua states
- timers, signals, child processes, file-system operations, TCP, UDP and pipe transport and name resolution (the calls that wait are suspending calls)
- virtual clock for tests

## Non-goals

- network protocols (see `net`)
- OS threads running Lua code, except the self-contained functions of `offload`, each in the separate Lua state of a libuv pool thread

## Standards and references

- Schmidt, *Reactor* (1995)
- Hoare, *CSP* (1978)
- structured concurrency (Sústrik 2016; Smith 2018)

## Public API

Implemented. Every function marked *suspends* is `---@async` and raises
`NonYieldableContextError` outside a managed coroutine or inside a non-yieldable C boundary.
`fork`, `detach`, `with_ambient` and `ambient` do not suspend (`with_ambient` only if its `fn` does): they need a managed
coroutine and raise the same error otherwise, but carry no `---@async` tag. `tests/unit/suspension_test.lua` checks that
the tags match what the functions do.

| Name | Description |
|---|---|
| `reactor.run(fn, ...)` | Runs `fn` on a new real-clock reactor until it and everything it forked have finished. |
| `reactor.Reactor({ clock = "real"\|"virtual", start = 0, on_unobserved_failure = fn, max_offloads = n })` | The scheduler; `:run(fn, ...)`, `:now()`, `:live_coroutines()`, `:is_real()`; `Reactor.open_handles()` counts the open libuv handles (leak tests, task `leaks`). The virtual clock jumps to the next timer when nothing is ready (deterministic tests). |
| `reactor.is_future(value)` | Whether `value` is a `Future`. |
| `reactor.fork(fn, ...)` | Does not suspend; managed coroutines only (raises otherwise). Starts `fn` in the current scope, returns a `Future`. |
| `reactor.join(f1, ...)` | *suspends*. Values in argument order; the first failure cancels the others and is raised. |
| `reactor.select(f1, ...)` | *suspends*. Returns `index, value` of the first future to finish; cancels the others. If several are already ready, the first in argument order wins (a priority order, not random). |
| `reactor.sleep(seconds)` | *suspends*. `0` yields to the other ready coroutines. |
| `reactor.scope(fn)` | *suspends*. Runs `fn(scope)`; returns only after every child has completed or been cancelled; raises the first failure. |
| `reactor.deadline(seconds_or_instant, fn, ...)` | *suspends*. Cancels `fn` and raises `DeadlineExceededError` when late. A limit of zero or less, or a past `Instant`, expires immediately (`fn` is cancelled at its first suspension point); a non-finite number raises `ArgumentError`. |
| `reactor.now()`, `reactor.at(seconds)`, `reactor.Instant` | Reading of the running clock; absolute `Instant` (a class) for `deadline` (OQ-22). |
| `reactor.shield(limit, fn, ...)` | *suspends*. Runs `fn` shielded from cancellation (OQ-23): neither the cancellation of enclosing scopes nor one requested on the running computation is delivered inside `fn`, so cleanup can suspend (flush, close handshake) while its scope is cancelled. `limit` (seconds or `reactor.at(...)`) is the shield's own deadline and is required; on expiry the shield raises `DeadlineExceededError` (zero, negative or past limits expire immediately, as for `deadline`). A cancellation that arrived meanwhile is raised again at the first suspension point after the shield. The caller owns the bound (there is no cap on `limit`); nested shields each keep their own deadline and bound their own body only; a body that never suspends is not bounded. |
| `reactor.detach(fn, ...)` | Does not suspend; managed coroutines only (raises otherwise). Starts `fn` in the application scope; its failure is seen through its future; when nothing waits for the future as it fails, the `on_unobserved_failure(err, future)` option of the reactor is called (OQ-26 (1)). |
| `reactor.with_ambient(key, value, fn, ...)`, `reactor.ambient(key)` | Ambient context (ADR 0025): immutable bindings visible in `fn` and in computations forked or detached from it; `ambient` is also `reactor.ambient`. Managed coroutines only. |
| `reactor.fs` | *suspend*: `read_file(path)`, `write_file(path, data)`, `stat(path)` (nil if absent, also when a path component is not a directory, `ENOTDIR`), `remove`, `mkdir`, `rmdir`, `list(path)` (a failed scan raises `IoError`). A path with an embedded NUL byte raises `ArgumentError`. Real clock only; failures raise `reactor.IoError` (`context.errno`). |
| `reactor.wait_signal(name, ...)` | *suspends*. Returns the name of the first signal delivered (`"sigint"`, `"sigterm"`, ...). |
| `reactor.watch_signals(name, ...)` | Returns a `SignalWatcher` that owns its libuv signal handles from creation until `close()` (also `<close>`; idempotent). `watcher:wait()` *suspends* until a signal is delivered and returns its name; a signal delivered while nobody waits is queued (at most 16, a name already queued is not queued twice, the 17th is dropped) and returned by the next `wait()`, so none falls in the window between two waits. `watcher:pending()` is the queue length, `watcher:is_closed()`. Cancelling a waiter keeps the watcher and its queue; closing wakes a waiter with an error; one coroutine may wait at a time. The handles do not keep the loop alive while nobody waits. `ArgumentError` for no name or a non-string; `IoError` (`watch_signals`) for a name the platform refuses, like `wait_signal`. |
| `reactor.run_process(program, args)` | *suspends*. Runs a program, returns `{ code, signal, stdout, stderr }`; the child is killed on cancellation and reaped (an uncancellable wait bounded by the kill) before the call raises. `program` must be a non-empty string and `args` a sequence of strings, without NUL bytes (`ArgumentError`). It inherits this process's environment without the marker of its own message pipe, and does not inherit that pipe. On Windows a child ended by `kill` reports `code` 1 and `signal` 0: detect a crash by `code` there. |
| `reactor.spawn(program, args?, options?)` | Starts a long-lived child and returns a `Process` at once (`.pid`, `.ipc`, `:wait()` *suspends*, `:kill(signal?)`, `:is_running()`). Options: `env` (added to the inherited environment; names are case-insensitive on Windows), `cwd`, `ipc` (message pipe), `stdout`/`stderr` (`"inherit"` default or `"ignore"`). The environment marker of the message pipe wins over a `env` entry of the same name. `program` and `args` are validated as for `run_process`. The caller waits for or kills the child and closes `process.ipc`. Only a child started with `ipc = true` holds the message pipe: a process it starts in turn gets neither the pipe nor the environment marker. A running child keeps the libuv loop alive (waiting for it with nothing else pending is no deadlock); `reactor.run` returns when its main coroutine ends, running child or not. `kill` is a signal operation, not the cancellation mechanism (`reactor.scope`, `reactor.deadline`): it treats an already vanished child (`ESRCH`) as success and raises `IoError` for an invalid signal. **Windows:** only `SIGTERM`, `SIGKILL`, `SIGINT` and `0` are supported (others fail with `ENOSYS`), a killed child reports `code` 1 and `signal` 0, a program is looked up in the working directory first and then in `PATH`, `.cmd` and `.bat` scripts cannot be started directly (run `cmd.exe /c`), and `"inherit"` needs a valid standard output and error in this process (a service without them: pass `"ignore"`). |
| `reactor.ipc` | Framed message pipe between parent and child (ADR 0023). `process.ipc` is the parent's `Peer`, `reactor.ipc.parent(options?)` the child's (nil when started without `ipc`; the same peer on every call; the environment marker is removed once the pipe is open). `Peer:send(message, stream?, options?)` (*suspends*) sends a string of at most `max_message` bytes (default 16 MiB) and optionally hands a `TcpStream` over (closed in the sender afterwards, unless `options.keep_open` is true: the caller then closes it, for example once the receiver acknowledged it; a stream in flight is held by no process, and macOS may discard it); `Peer:receive()` (*suspends*) returns `message, stream?`, nil when the other end closed; `:close()`, `:is_closed()`. `reactor.Peer(handle, { max_message })` and `ipc.parent({ max_message })` set the size limit, applied to what is sent and received. A cancelled receive keeps the peer open and loses nothing; a malformed frame, or a stream that arrives without or against its announcement, raises `TransportError` `EPROTO` and closes the peer; a pipe that ends inside a frame raises `EPIPE`; a closed peer raises `EBADF` (`ECANCELED` for a coroutine waiting while it closes). Messages are strings: serialising them is the caller's concern. **Windows:** the stream is duplicated for the receiver and the duplicate is valid only while the sender's socket is open, and the sender closes it when `send` returns: have the receiver acknowledge with a message before the sender exits. |
| `reactor.supports_spawn()`, `reactor.supports_handle_passing()` | `true`, or `false` and a reason, like `supports_reuseport`. They check that luv provides process creation and an IPC pipe with `write2` (nothing is started or passed); verified on Linux only, libuv provides both on macOS and Windows. |
| `reactor.supports_reuseport()` | Whether `listen_tcp(..., { reuseport = true })` works here (probed once). Needs luv with TCP `reuseport` (OQ-43); otherwise `listen_tcp` raises `TransportError` `ENOTSUP` rather than ignoring the option. Says nothing about balance: macOS accepts the flag and does not balance. |
| `reactor.system_name()` | Name of the operating system as libuv reports it (`Linux`, `Darwin`, `Windows_NT`, ...). Does not suspend. |
| `reactor.available_parallelism()` | Processing units this process may use, at least 1: the default count of workers (ADR 0023). Does not suspend. |
| `reactor.offload(fn, ...)` | *suspends*. Runs `fn(...)` on the libuv thread pool, in the separate Lua state of a pool thread (a fresh environment per call), and returns its results ([concurrency.md, "Offload"](../../docs/architecture/concurrency.md#offload), OQ-119). `fn` must be a Lua function with no upvalue other than `_ENV`, compiled with debug information (`ArgumentError` otherwise), and must not suspend. Arguments and results are copied (`nil`, booleans, numbers, strings, plain tables; the exact rules are in the specification). An error of `fn` raises `reactor.OffloadError` (`context.reason`, `context.traceback`, `context.code`). At most `max_offloads` functions (a `Reactor` option; default the pool size minus one, at least 1) are on the pool at once, the others wait in a first-in-first-out queue; a caller cancelled while queued is removed and its function never runs. A running function cannot be interrupted: its cancelled caller is released at once and the late result discarded, and `reactor.run` returns only once every running function has returned. Real clock only. The pool (4 threads, `UV_THREADPOOL_SIZE`) is shared with `fs` and `resolve`. |
| `reactor.resolve(host, options?)` | *suspends*. Resolves a host name or numeric address to `{ ip, family }` entries in the resolver's order (option `family`: `"inet"` or `"inet6"`). Failure raises `TransportError` (`errno` such as `EAI_NONAME`); cancellation releases the caller at once and discards the late result (OQ-32). |
| `reactor.connect_tcp(host, port, options?)` | *suspends*. Connects to a numeric address (no name resolution, OQ-30); returns a `TcpStream`. Bound it with `deadline`; cancellation abandons the attempt and closes its handle. Options: `nodelay` (default `true`), `keepalive` (default `false`), `keepalive_delay` (a positive integer number of seconds, default 60); `backlog` and `reuseport` belong to `listen_tcp` and raise `ArgumentError` here. |
| `reactor.listen_tcp(host, port, options?)` | Binds and listens (port 0 picks a free port); returns a `TcpListener`. Options as above plus `backlog` (default 128); accepted streams inherit `nodelay` and `keepalive`. |
| `TcpStream` | `:read(max?)` (*suspends*) returns at most `max` bytes, nil at end of stream, never an empty string; cancelling keeps the stream open and loses no data. `:write(data)` (*suspends*) returns once the bytes were handed to the system (back-pressure); a cancelled write closes the stream. `:shutdown()` (*suspends*) half-closes; `:close()` is idempotent and never suspends, `local s <close> = ...` closes on scope exit; `:is_closed()`, `:peer_address()`, `:local_address()` (`{ ip, port, family }`), `:set_nodelay(bool)`, `:set_keepalive(bool, delay?)`. Failures raise `TransportError` (a `core.NetworkError`) (`context.errno`: libuv name; `EBADF` after close, `ECANCELED` when closed while waiting). Once read, the stream reads ahead of its reader by up to 64 KiB, then stops reading from the socket until the reader caught up (back-pressure). |
| `TcpListener` | `:accept()` (*suspends*) returns a `TcpStream`; cancelling keeps the listener and queued connections; a connection whose peer already reset it (`EINVAL`, `ENOTCONN`, `ECONNRESET`, `ECONNABORTED` while applying the options, seen on BSD and macOS) is closed and skipped. `:close()`, `:is_closed()`, `:local_address()`; `<close>`-able. Connections are not guaranteed to be accepted in arrival order (libuv on Windows hands pending ones out last-in first-out). |
| `reactor.bind_udp(host, port)` | Binds a `UdpSocket` (port 0 picks a free port; numeric addresses only). `:send_to(host, port, data)` (*suspends*; a send cancelled before it completed closes the socket), `:receive_from()` (*suspends*; returns `data, from`; cancelling keeps the socket and loses no datagram; one coroutine receives at a time, a second one raises), `:local_address()`, `:close()`, `:is_closed()`, `<close>`. Failures raise `TransportError`. |
| `reactor.connect_pipe(path)`, `reactor.listen_pipe(path, options?)` | `connect_pipe` *suspends*. Unix-domain sockets (named pipes on Windows); `PipeStream` and `PipeListener` behave like their TCP counterparts (`:path()` too). `listen_pipe` options: `backlog` (positive integer, default 128, ignored on Windows) and `mode`: `"owner"` (default, the socket file is restricted to its owner), `"readable"` (0444), `"writable"` (0222) or `"readwrite"` (0666), open to every user with that access. Connecting to a Unix-domain socket requires write permission, so `"readable"` is of no use for connecting on POSIX: `"writable"` or `"readwrite"` is what lets other users connect. The socket is bound in a private `0700` directory and linked to the path with its final permissions, so it is never visible with wider ones; only a file system without hard links (`EPERM`, `ENOTSUP`, `EOPNOTSUPP`, `EXDEV`, `ENOSYS`, `EMLINK`) falls back to a direct bind followed by a `chmod`, with an exposure window (permissions derived from the umask, which Lua cannot set), and any other link failure raises `TransportError`. Closing the listener removes the socket file only if the file at the path is still the socket it linked (same device and inode). A path with an embedded NUL byte raises `ArgumentError` (a leading NUL names an abstract socket on Linux). `mode` has no effect on Windows. The path must not exist (`EADDRINUSE`); the socket path is limited to at most 107 bytes (103 on macOS), excluding the terminating NUL, a Windows pipe name to 256 characters. |
| `Future` | `:value()` (*suspends*), `:cancel()`, `:done()`, `:state()` (`pending`, `completed`, `failed`, `cancelled`). |
| `Scope` | `:fork(fn, ...)`, `:cancel(err?)` (the optional error is what the children are cancelled with), `:is_cancelled()`, `:live()`. |
| `reactor.Channel(capacity)` | `:send(v)`, `:receive()` (*suspend*), `:close()` (returns whether this call closed it), `:is_closed()`, `:length()`, `:capacity()`; capacity 0 is a rendezvous channel. Receivers drain the buffer of a closed channel, then `ClosedChannelError` is raised; sends on a closed channel raise it too. `:receive_op()` and `:send_op(v)` build operations for `select`. |
| `reactor.Semaphore(n)` | `:acquire()` (*suspends*) returns a `Permit`; `:try_acquire()`, `:release()` (adds a unit), `:available()`, `:waiting()`. FIFO, no barging. |
| `reactor.Mutex()` | `:lock()` (*suspends*) returns a `Permit`; `:try_lock()`, `:is_locked()`, `:waiting()`. |
| `reactor.Monitor()`, `reactor.Condition` | `monitor:enter()` (*suspends*) returns a `Permit`; `monitor:is_entered()`; `monitor:condition()` creates a `Condition`; `condition:wait()` (*suspends*), `:notify()`, `:broadcast()`, `:waiting()`. Mesa semantics: test the predicate in a loop (OQ-25). |
| `Permit` | `:release()` (idempotent), `:is_held()`; closing it releases it: `local permit <close> = mutex:lock()`. |

`TcpStream`, `TcpListener`, `UdpSocket`, `PipeStream`, `PipeListener`, `Process`, `Future`, `Scope` and `Permit` are returned by the calls above and are not constructed by users (their `init` is private). Constructors meant for users: `Reactor`, `Channel`, `Semaphore`, `Mutex`, `Monitor` and `Peer(handle, options)`.

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
