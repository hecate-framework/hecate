# Concurrency (`hecate.reactor`)

Status: implemented in Phase 1 (`offload`: Phase 2); decisions in [ADR 0002](../adr/0002-libuv-via-luv.md) and
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
| `deadline(seconds_or_instant, fn, ...)` | Run `fn`; raise `DeadlineExceededError` and cancel it if it does not finish in time. Accepts a relative duration or an absolute instant. |
| `sleep(seconds)` | Suspend the current coroutine. |
| `detach(fn, ...) → Future` | Start `fn` in the application scope, outside the current scope; its failure is seen only through its future (rule 2). |
| `scope(fn)` | Open a structured-concurrency scope: returns only when every computation forked inside has completed or been cancelled. |
| `with_ambient(key, value, fn, ...) → ...` | Run `fn` with `key` bound to `value` in the running computation and in what it forks or detaches meanwhile (see "Ambient context"). |
| `ambient(key) → value` | The value bound to `key`, or `nil`. |
| `Future` | `:value()` (suspends until ready), `:cancel()`, `:done()`, `:state()`. |
| `Channel(capacity)` | `:send(v)`, `:receive()`, `:close()`; capacity 0 is a rendezvous channel. Usable in `select`. |
| `Semaphore(n)`, `Mutex()`, `Monitor()`, `Condition` | Classical synchronisation. `Mutex` and `Semaphore` permits are `<close>`-able. A `Monitor` follows Mesa semantics: `Condition:notify` does not hand over the monitor, so a woken waiter re-enters later and must wait in a `while` loop that re-tests its predicate. |
| `now()`, `at(seconds)`, `Instant` | Reading of the running clock; absolute instants for `deadline`. |
| `offload(fn, ...)` | (Phase 2, not yet implemented; OQ-27.) Run a pure function on the libuv thread pool (no access to Lua state other than its arguments; see "Blocking work"). |

## Structured concurrency

Every forked computation belongs to a **scope**. The kernel opens a scope per request;
the test framework opens one per test. Rules:

1. A scope does not complete before all of its children have completed.
2. If a child fails, the scope cancels its siblings and propagates the error (unless the
   child was explicitly detached into the application scope, an operation that must be
   visible in code: `reactor.detach(fn)`).
3. When a request is aborted (client disconnect, deadline), its scope is cancelled.
4. Cancellation is **cooperative**: it is delivered as a `CancellationError` raised at
   the next suspension point of the cancelled coroutine, and again at every later suspension
   point of the cancelled scope (level-triggered, OQ-23). Cleanup in `<close>` variables runs
   normally but cannot suspend while its scope is cancelled (OQ-23).

This removes the classic leak where background work outlives the request that started it.

## Ambient context

[ADR 0025](../adr/0025-ambient-context.md). Request-scoped values (a request id, a principal) reach every
computation forked while serving a request without being passed through each function.

- `with_ambient(key, value, fn, ...)` binds `key` to `value` while `fn` runs and returns the results of `fn`. A nested
  binding of the same key shadows the outer one until `fn` returns; the binding is removed when `fn` returns or raises.
- `ambient(key)` returns the value bound in the running computation, or `nil`.
- `fork`, `detach` and `Scope:fork` give the new computation the bindings visible **at the moment of the call**, from
  the creator (not from the application scope). Bindings made later by the creator are not seen by the child, and a
  binding made by a child is seen by neither its parent nor its siblings.
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
  `operation` in its context); `IoError` stays for the file system and processes.
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
- `offload` for Lua functions requires a separate Lua state per pool thread with
  serialised arguments and results; it is a later addition (Phase 2+), specified before
  implementation.

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
  `stop(deadline)`, `reload` and counters; a worker whose control message pipe closes drains and exits.
- Graceful shutdown: stop accepting, drain in-flight requests up to a configurable deadline,
  then cancel remaining scopes. A rolling reload starts the replacement before stopping the old
  worker.

## Signals and shutdown

`SIGINT`/`SIGTERM` (and Windows console control events) trigger graceful shutdown.
`SIGHUP` reloads configuration where supported. All handled through libuv signal
handles.

## Testing requirements

- Deterministic scheduler mode for tests (virtual clock for `sleep` and deadlines).
- Property tests for `join`/`select`/cancellation interactions.
- Leak detection: a test fails if its scope ends with live children or open handles.
