# Concurrency (`hecate.reactor`)

Status: specification; decisions in [ADR 0002](../adr/0002-libuv-via-luv.md) and
[ADR 0003](../adr/0003-transparent-structured-concurrency.md) (both Accepted).

## Model

- One OS process runs one **reactor** (libuv loop through luv) on one thread.
- Every unit of work (request, background job, test) is a Lua **coroutine** managed by
  the reactor's scheduler.
- I/O operations exposed by Hecate are **transparent**: they look synchronous, but
  internally submit the operation to libuv and `yield` the current coroutine; the
  scheduler resumes it with the result. Application code never sees callbacks.
- Throughput across CPU cores is obtained with **several processes** (workers), not
  threads. See "Workers" below.

## Primitives

All primitives live in `hecate.reactor`. Names follow [the glossary](../glossary.md).

| Primitive | Semantics |
|---|---|
| `fork(fn, ...) → Future` | Start `fn` in a new coroutine in the current scope. |
| `join(f1, f2, ...) → v1, v2, ...` | Wait for all futures; if one fails, cancel the others in the same `join` and raise the first error. |
| `select(f1, f2, ...) → index, value` | Wait for the first future to complete; cancel the others. |
| `deadline(seconds_or_instant, fn, ...)` | Run `fn`; raise `DeadlineExceededError` and cancel it if it does not finish in time. Accepts a relative duration or an absolute instant. |
| `sleep(seconds)` | Suspend the current coroutine. |
| `scope(fn)` | Open a structured-concurrency scope: returns only when every computation forked inside has completed or been cancelled. |
| `Future` | `:value()` (suspends until ready), `:cancel()`, `:done()`, `:state()`. |
| `Channel(capacity)` | `:send(v)`, `:receive()`, `:close()`; capacity 0 is a rendezvous channel. Usable in `select`. |
| `Semaphore(n)`, `Mutex()`, `Monitor()`, `Condition` | Classical synchronisation. `Mutex` and `Semaphore` permits are `<close>`-able. |
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
   the next suspension point of the cancelled coroutine. `<close>` variables and
   `finally`-style cleanup run normally.

This removes the classic leak where background work outlives the request that started it.

## Suspension points and shared state

Because suspension is invisible in code, the documentation must state precisely which
calls may suspend: **every I/O operation, every primitive above, and nothing else**.
Pure computations never yield.

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

## Blocking work

- File-system operations go through libuv's asynchronous file API (already off-thread).
- SQLite queries and CPU-heavy native work run on the libuv thread pool through native
  bindings designed for it. Only C code runs on pool threads; the Lua state is never
  touched outside the reactor thread.
- `offload` for Lua functions requires a separate Lua state per pool thread with
  serialised arguments and results; it is a later addition (Phase 2+), specified before
  implementation.

## Workers

- `hecate serve --workers N` (default: number of CPU cores) starts one primary process
  and N worker processes.
- Linux: workers bind with `SO_REUSEPORT` for kernel-level load balancing.
- macOS and Windows: the primary owns the listening socket and shares it with workers
  through libuv IPC handle passing. To be validated (OQ-8).
- The primary supervises workers (restart on crash with backoff), propagates signals,
  and coordinates graceful shutdown: stop accepting, drain in-flight requests up to a
  configurable deadline, then cancel remaining scopes.

## Signals and shutdown

`SIGINT`/`SIGTERM` (and Windows console control events) trigger graceful shutdown.
`SIGHUP` reloads configuration where supported. All handled through libuv signal
handles.

## Testing requirements

- Deterministic scheduler mode for tests (virtual clock for `sleep` and deadlines).
- Property tests for `join`/`select`/cancellation interactions.
- Leak detection: a test fails if its scope ends with live children or open handles.
