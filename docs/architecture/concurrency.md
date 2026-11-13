# Concurrency (`hecate.reactor`)

Status: implemented in Phase 1, `offload` in Phase 2; decisions in [ADR 0002](../adr/0002-libuv-via-luv.md) and
[ADR 0003](../adr/0003-transparent-structured-concurrency.md) (both Accepted).

## Model

- One OS process runs one **reactor** (libuv loop through luv) on one thread.
- Every concurrent computation (request, background job, test) is a Lua **coroutine** managed by
  the reactor's scheduler.
- I/O operations exposed by Hecate are **transparent**: they look synchronous, but
  internally submit the operation to libuv and `yield` the current coroutine; the
  scheduler resumes it with the result. Application code never sees callbacks.
- Throughput across CPU cores is obtained with **several processes** (workers), not
  threads. See "Workers" below.

## Primitives

All primitives live in `hecate.reactor`. Names follow [the glossary](../glossary.md). The table lists the
concurrency primitives; transport, name resolution, `fs`, `wait_signal`, `run_process`, `spawn`, `Scope` and
`Permit` are specified in the sections below, and the complete list with signatures is in
[the package README](../../packages/reactor/README.md).

| Primitive | Semantics |
|---|---|
| `fork(fn, ...) → Future` | Start `fn` in a new coroutine in the current scope. |
| `join(f1, f2, ...) → v1, v2, ...` | Wait for all futures; if one fails, cancel the others in the same `join` and raise the first error. |
| `select(f1, f2, ...) → index, value` | Wait for the first future to complete; cancel the others. If several are already ready, the first in argument order wins: the arguments are a priority order, not a random choice (a caller that wants fairness rotates them). |
| `deadline(seconds_or_instant, fn, ...)` | Run `fn`; raise `DeadlineExceededError` and cancel it if it does not finish in time. Accepts a relative duration or an absolute instant; a duration of zero or less, or an instant already past, is allowed and expires immediately (the body is cancelled at its first suspension point). Non-finite values raise `ArgumentError`. |
| `shield(seconds_or_instant, fn, ...)` | Run `fn` shielded from cancellation (see rule 4): the cancellation of the enclosing scopes is not delivered inside `fn`, so cleanup can suspend. The shield has its own deadline (required: no default is decided); on expiry it is cancelled and raises `DeadlineExceededError`; as for `deadline`, a zero, negative or past limit expires immediately. The caller owns the bound (no cap on the limit); nested shields each keep their own deadline and bound their own body only; a deadline is delivered at suspension points, so a body that never suspends is not bounded. |
| `sleep(seconds)` | Suspend the current coroutine. |
| `detach(fn, ...) → Future` | Start `fn` in the application scope, outside the current scope; its failure is seen only through its future (rule 2). |
| `scope(fn)` | Open a structured-concurrency scope: returns only when every computation forked inside has completed or been cancelled. |
| `with_ambient(key, value, fn, ...) → ...` | Run `fn` with `key` bound to `value` in the running computation and in what it forks or detaches meanwhile (see "Ambient context"). |
| `ambient(key) → value` | The value bound to `key`, or `nil`. |
| `Future` | `:value()` (suspends until ready), `:cancel()`, `:done()`, `:state()`. |
| `Channel(capacity)` | `:send(v)`, `:receive()`, `:close()`; capacity 0 is a rendezvous channel. Usable in `select`. |
| `Semaphore(n)`, `Mutex()`, `Monitor()`, `Condition` | Classical synchronisation. `Mutex` and `Semaphore` permits are `<close>`-able. A `Monitor` follows Mesa semantics: `Condition:notify` does not hand over the monitor, so a woken waiter re-enters later and must wait in a `while` loop that re-tests its predicate. |
| `now()`, `at(seconds)`, `Instant` | Reading of the running clock; absolute instants for `deadline`. |
| `offload(fn, ...) → ...` | Run a self-contained Lua function on the libuv thread pool, in a separate Lua state, and suspend until it returns (see "Offload"). |

## Structured concurrency

Every forked computation belongs to a **scope**. The kernel opens a scope per request;
the test framework opens one per test. Rules:

1. A scope does not complete before all of its forked computations have completed.
2. If a forked computation fails, the scope cancels its siblings and propagates the error (unless the
   computation was explicitly detached into the application scope, an operation that must be
   visible in code: `reactor.detach(fn)`). A detached failure that nothing waits for when
   it happens is reported to the `on_unobserved_failure(err, future)` hook of the reactor
   (OQ-26 (1)), which `kernel` binds to `log`; without a hook it stays silent. The hook
   is not called for a cancelled computation, and an error it raises is discarded.
3. When a request is aborted (client disconnect, deadline), its scope is cancelled.
4. Cancellation is **cooperative**: it is delivered as a `CancellationError` raised at
   the next suspension point of the cancelled coroutine, and again at every later suspension
   point of the cancelled scope (level-triggered, OQ-23). Cleanup in `<close>` variables runs
   normally but cannot suspend while its scope is cancelled, unless it runs in `reactor.shield(limit, fn)`:
   inside a shield no cancellation of the enclosing scopes (nor of the running computation) is delivered, the
   shield's own deadline bounds it, and a cancellation that arrived meanwhile is raised again at the first
   suspension point after it. Computations forked inside a shield belong to the shield's scope and are not cancelled
   by the outer one.

This removes the classic leak where background work outlives the request that started it.

## Ambient context

[ADR 0025](../adr/0025-ambient-context.md). Request-scoped values (a request id, a principal) reach every
computation forked while serving a request without being passed through each function.

- `with_ambient(key, value, fn, ...)` binds `key` to `value` while `fn` runs and returns the results of `fn`. A nested
  binding of the same key shadows the outer one until `fn` returns; the binding is removed when `fn` returns or raises.
- `ambient(key)` returns the value bound in the running computation, or `nil`.
- `fork`, `detach` and `Scope:fork` give the new computation the bindings visible **at the moment of the call**, from
  the creator (not from the application scope). Bindings made later by the creator are not seen by the forked computation, and a
  binding made by a forked computation is seen by neither the computation that forked it nor its siblings.
- Bindings are immutable: a value that must change is a table its owner mutates, visibly. `key` is any non-nil value
  compared by equality; a module-private table avoids collisions between packages.
- Both functions raise `NonYieldableContextError` outside a managed coroutine.
- Representation: the bindings of a computation are a persistent linked list (one node per binding pointing to the
  outer one), so inheritance is O(1) and a lookup is O(nesting depth).

This is an exception to explicit passing: use it for ambient, cross-cutting values (logging, tracing), not for data a
function needs to do its work.

## Suspension points and shared state

Because suspension is invisible in code, the documentation must state precisely which
calls may suspend: **every I/O operation, `join`, `select`, `sleep`, `scope`, `deadline`, and the
channel and lock operations, and nothing else**. `fork`, `detach`, `with_ambient` and `ambient` do not
suspend; they only require a managed coroutine.
Pure computations never yield. A test (`packages/reactor/tests/unit/suspension_test.lua`) checks that the
`---@async` tags of `hecate.reactor` match the calls that actually yield.

Guidance for users (to appear in the website's "Explanation" section):

- Avoid module-level mutable state. Use the container's scoped services.
- When shared state is unavoidable, protect read-modify-write sequences that span a
  suspension point with a `Mutex` or use atomic operations of the provided cache.

## Non-yieldable contexts

Lua cannot yield across some C boundaries. Known cases: the comparator of `table.sort`,
the replacement function of `string.gsub`, metamethods invoked from C functions that do
not support continuations, `require` while loading a module. Calling a suspending
operation there raises `NonYieldableContextError` with an explanatory message.
The reactor must detect this case (via `coroutine.isyieldable`) rather than letting
Lua report a generic "attempt to yield across a C-call boundary".

## Transport

`hecate.reactor` wraps libuv's network handles once, so that `net` never requires `luv`
(ADR 0002, OQ-28): `connect_tcp`, `listen_tcp`, `bind_udp`, `connect_pipe`, `listen_pipe`
and `resolve` suspend the calling coroutine and return streams, listeners and sockets with
`read`, `write`, `accept`, `receive_from`, `send_to`, `shutdown` and `close`.

- A failure of the transport raises `TransportError`, a `NetworkError` (with `errno` and
  `operation` in its context); `IoError` (a subclass of `core.IoError`) stays for the file system and processes.
- A cancelled `read`, `accept` or `receive_from` leaves the object usable and loses no data. A
  cancelled `write`, `send_to`, `shutdown` or `connect` closes it, because how much was sent
  is unknown. `close` is idempotent, never suspends and wakes every coroutine waiting on it.
- Operations take no timeout argument: bound them with `deadline`.
- One coroutine reads, accepts or receives at a time on an object.

## Blocking work

- File-system operations go through libuv's asynchronous file API (already off-thread).
- SQLite queries and CPU-heavy native work run on the libuv thread pool through native
  bindings designed for it. Only C code runs on pool threads; the Lua state is never
  touched outside the reactor thread.
- Lua functions run on the pool through `offload` (below): each pool thread has its own Lua
  state, and arguments and results are copied between states, never shared.

## Offload

Specified in Phase 2 (OQ-27); the choices below were confirmed or decided by the owner (OQ-119, 2026-11-12).

`offload(fn, ...)` runs `fn(...)` on libuv's thread pool and suspends the calling coroutine until it
returns, so CPU-bound work (hashing a password, compressing, parsing a large document) does not stall
the reactor thread. The basis is luv's `new_work` and `queue_work`; luv is used unmodified (OQ-1).

- **The function is self-contained.** `fn` must be a Lua function (not a C function) whose only
  upvalue, if any, is `_ENV`: it is copied to the pool thread as bytecode (`string.dump`), and
  upvalues do not survive the copy. A function with any other upvalue raises `ArgumentError`
  before anything is queued, and so does a stripped function (bytecode without debug
  information), whose upvalues cannot be checked. On the pool thread `_ENV` is a fresh table per
  call whose reads fall through to that state's global table, with the standard libraries and
  `require` (searching the `LUA_PATH` and `LUA_CPATH` of the process environment, not the
  `package.path` the reactor thread may have changed at run time); a function written under its
  own `local _ENV` gets this environment instead of its own.
- **Separate state.** Each pool thread owns one Lua state, created on first use and kept for the
  life of the process. `fn` sees nothing of the reactor thread: no globals, no loaded modules, no
  reactor. It must not suspend (there is no reactor there) and must not rely on what an earlier
  call left in its state (calls are spread across threads in no particular order). An assignment
  to a global stays in the call's own environment; changing the global table through `_G` or the
  standard library tables is not supported, since it affects every later call on that thread.
- **Values that cross.** Arguments and results are copied: `nil`, booleans, numbers (the integer or
  float subtype is kept), strings (any bytes) and *plain tables* built from them: tables without a
  metatable whose keys are booleans, numbers or strings and whose values are any of these values.
  Nesting is limited to 100 levels. A cycle, a table with a metatable, or any other value
  (function, userdata, thread) raises `ArgumentError` for an argument, or `OffloadError` for a
  result. A table reached twice is copied twice (sharing is not preserved). There is no limit on
  the number of arguments or results, and `nil` arguments and results are kept in place.
- **Errors.** An error raised by `fn` is raised in the caller as `hecate.reactor.OffloadError`
  (a `hecate.core.Error`) with `context.reason` `"raised"`: the message is `reactor.offload:`
  followed by the error message (the `message` field of an error object, otherwise `tostring` of
  the error), `context.traceback` holds the traceback on the pool thread and `context.code` the
  `code` of a framework error. The original error object does not cross. A result that cannot be
  copied gives the reason `"result"`, a failure of the pool thread itself `"worker"` (both
  without a traceback). libuv refusing the work raises `hecate.reactor.IoError`.
- **Queue and limit.** At most `max_offloads` functions are on the pool at once (a `Reactor`
  option, a positive integer; default the pool size minus one, at least 1), so a thread stays free
  for the file system and name resolution. The other calls wait in a queue kept by `offload` in
  Lua, first in first out. libuv's own queue is not used for them because luv does not expose the
  cancellation of a queued `uv_work_t` (luv issues 416 and 630, open).
- **Cancellation.** A caller cancelled while its call is queued is removed from the queue and its
  function never runs; so is a caller closed by the teardown of a failed run. A function already
  running cannot be interrupted: libuv never stops a started work request, and stopping Lua code
  in another state would need native code. Its cancelled caller is released at once and the late
  result is discarded, as for `resolve`; the pool thread stays busy until `fn` returns. Bound the
  work itself (input size, number of rounds), not only the wait. There is no deadline for a
  running function: a count hook in the pool-thread state could raise once a deadline has passed,
  but any count hook doubles the time of pure-Lua code in Lua 5.5, whatever its interval (owner
  decision, OQ-119 (8)).
- **End of a run.** `Reactor:run` returns only once every running function has returned, even
  those whose callers were cancelled, so a function that never returns keeps the program from
  ending. luv 1.53 crashes when the Lua state closes while work is in flight: at `lua_close` it
  closes the pool-thread states (`luv_work_cleanup`) before running the loop to completion
  (`loop_gc`), whose completion callback then enters the closing state. Programs that end with
  `uv.run()` never meet it, because that call returns only when no work is left; the reactor
  stops driving the loop when its main computation ends. Queued calls of finished callers are
  dropped and do not delay the end.
- **Clock.** Like the file system, `offload` needs the real clock; on a virtual-clock reactor it
  raises `hecate.core.Error`.
- **Pool size.** The libuv pool is one per process, shared with the file system and name
  resolution, and has 4 threads by default; the environment variable `UV_THREADPOOL_SIZE`, read
  when the pool is first used, changes it (from 1 to 1024). Its threads never exit and its size
  never changes: a program that offloads a lot sets `UV_THREADPOOL_SIZE` before it starts (the
  advice Node.js gives for the same pool). An elastic pool would need threads owned by Hecate,
  native code the owner declined (OQ-119).
- **Cost.** Each call copies its arguments and results and loads the bytecode of `fn` on the pool
  thread: a round trip costs tens of microseconds, and the copy is proportional to the size of
  the values, encoded and decoded on the reactor thread for the arguments and the results
  (`packages/reactor/benchmarks/offload.lua`). It is worth it for work of a millisecond or more,
  not for short functions or for a large value with little work. Memory is a cost too: what `fn`
  allocates stays in the pool thread's Lua state after the call, as garbage that state collects only
  when that thread runs Lua again, so a program can hold up to the pool size times the peak
  allocation of one call (one call building 3 million strings left about 300 MB resident). A
  function that builds large data drops it before returning: it clears its references to that data
  (or builds it in an inner function that has returned) and then calls `collectgarbage()`.

## Workers

Accepted in [ADR 0023](../adr/0023-multi-process-serving.md), measured in
[the OQ-8 spike](../spikes/OQ-8-multi-process.md).

- `hecate serve --workers N` (default: number of CPU cores) starts one primary process
  and N worker processes. A worker is the same program with a worker role: its own Lua state
  and reactor, nothing shared.
- `reactor` provides the mechanism: `spawn` (a long-lived child), `ipc` (framed messages
  between parent and child, with handle passing) and the TCP `reuseport` option. `kernel`
  provides the policy: the supervisor and the listening strategies.
- A **listening strategy** decides where a worker accepts connections from; the code above it
  is identical on every platform. `reuseport` (Linux default): each worker binds the port with
  `SO_REUSEPORT`, the kernel balances, the primary is not in the data path.
  `round_robin` (macOS and Windows, and the fallback when a strategy is not supported): the
  primary accepts and passes each connection to the next worker through IPC handle passing. A
  listening socket shared by all workers was measured and balances on no platform. Linux is never
  constrained by what another platform needs.
- The primary supervises workers (readiness, restart on crash with exponential backoff and a
  crash-loop limit) over a control message pipe that exists on every platform and carries `ready`,
  `stop(deadline)` and counters, and, with `round_robin`, `connection` (with the stream handed over)
  from the primary and `received` from the worker; a worker whose control message pipe closes drains
  and exits. `reload` is reserved and unused (the rolling reload replaces workers by restart). The
  primary keeps its copy of each stream it hands over, in a FIFO per worker process, until the worker
  answers `received` (sent from a computation of its own once the stream is out of the frame, whether
  the worker queued or refused it), and closes what is still held when the message pipe ends or the
  worker exits or is killed: a stream in flight in a message pipe is held by no process, and macOS
  discards it when another Unix socket closes (OQ-118). The streams held for a worker are bounded by
  the connections in flight to it. A worker sends
  `counters <requests> <connections>` (two non-negative decimal integers, `-` for `requests` when it
  cannot count them) at most once per second and only when a value changed, from a computation of its
  own so that `stop` is never delayed, and once more when it has stopped serving; the primary keeps the
  latest values per worker (`Supervisor:counters()`), ignores a malformed message, and logs
  `hand_over_unaccounted` when a worker exits having accepted fewer connections than it was handed. Today `connections` counts the connections
  the hand-over listener accepted (`round_robin`) and `requests` is always unknown, `http.Server`
  having no request counter. A worker that does not send `ready` within `ready_timeout` seconds
  (default 30) of its start or restart is killed and counted as a crash (`worker_not_ready`); the watchdog ends at
  `ready`, and a worker retired by a reload drains under the reload's grace period, never cut short by it.
  Back-pressure of `round_robin`: a worker with as many unacknowledged hand-overs as its backlog is skipped; when every
  worker is saturated the connection is closed and `hand_over_saturated` is logged. In `degrade` mode a restart that
  cannot start the program counts as a crash and is retried; a failed first start stays `start_failed`.
  `HECATE_WORKER_HOST` may carry an IPv6 zone id.
- Graceful shutdown: stop accepting, drain in-flight requests up to a configurable deadline,
  then cancel remaining scopes. In a worker the drain of the hand-over queue counts within the grace period (its
  server gets what is left of it). A rolling reload starts the replacement before stopping the old
  worker.
- Signals (OQ-116): a worker ignores `SIGINT` and `SIGTERM`, because a terminal sends them to the
  whole process group; only the `stop` message of the primary ends a worker. The first signal in the
  primary stops the supervisor with the grace period (`server.grace_timeout`); a second one kills the
  workers at once. `workers` and `strategy` are the `Application` options, bound from the sibling
  configuration keys `server.workers` (default 1: the single process of before, with no supervisor)
  and `server.strategy`. The primary boots the application before it spawns, so a configuration or
  container error appears once.
- Rolling reload (`Supervisor:reload`, started by `SIGHUP` in the primary or by `Application:reload`): for
  each worker in turn the primary starts a fresh process from the same command, waits for its `ready`,
  adds it to the rotation, then stops the old worker with the grace period; an old worker is never taken
  out before its replacement is ready, a replacement that fails aborts the reload and leaves the old
  worker serving, and the planned exit is not a crash. It needs no worker-side message (`reload` stays
  reserved). With `reuseport` the connections queued in the closing socket of the old worker are reset
  by the kernel (ADR 0023, Decision 6); `round_robin` loses none.
  Both methods take one options table, `{ grace_timeout?, ready_timeout? }` (seconds the old worker
  drains, default 30 or the `grace_timeout` option; seconds a replacement may take to become ready,
  default 30).

## Signals and shutdown

`SIGINT`/`SIGTERM` trigger graceful shutdown on every platform (Windows delivers only
`SIGINT`, Ctrl+C, of the two). The set is fixed: it is not configurable, and an application
may turn the handling off. The first signal stops accepting and lets the requests in flight
finish for the grace period (configuration key `server.grace_timeout`, default 30 seconds);
a second signal during the drain cancels the remaining requests at once. `SIGHUP` starts the
rolling reload of the workers in the primary of a multi-process application (not on Windows) and is
ignored by a single process and by a worker. All handled through libuv signal handles (OQ-115). A loop that waits repeatedly uses a
persistent `SignalWatcher`, which queues signals delivered between two waits (OQ-116).

## Testing requirements

- Deterministic scheduler mode for tests (virtual clock for `sleep` and deadlines).
- Property tests for `join`/`select`/cancellation interactions.
- Leak detection: a test fails if its scope ends with live forked computations or open handles.
