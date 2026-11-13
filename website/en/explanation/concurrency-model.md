---
description: How hecate runs concurrent code - one reactor per process, coroutines that suspend transparently, the exact list of suspension points, structured concurrency with scopes, cooperative cancellation and processes for several cores.
hecate: "0.x"
lua: "5.5"
order: 8
---

# The concurrency model

This page explains how hecate runs many computations at once in one process, and the rules that keep them safe. It
is written for hecate 0.x and Lua 5.5. The decisions are ADR 0002 (libuv through luv) and ADR 0003 (transparent,
structured concurrency). For recipes, read [Concurrency](../how-to/concurrency.md).

## One reactor, many coroutines

A hecate process runs one [reactor](../reference/glossary.md#concurrency) on one thread: libuv's event loop, reached
through the luv binding. Every concurrent [computation](../reference/glossary.md#concurrency) (a request, a
background job, a test) is a Lua [coroutine](../reference/glossary.md#concurrency) that the reactor schedules.

When a coroutine starts an I/O operation, the reactor submits it to libuv and *suspends* the coroutine. Other
coroutines run meanwhile. When libuv reports the result, the reactor resumes the coroutine with it. One thread can
therefore wait on thousands of connections.

## Transparent suspension

Code that reads from a stream looks like code that blocks:

```lua
local line = reader:read_line()
writer:write("echo: " .. line .. "\n")
```

There is no `await`, no callback and no future returned by every call. Functions are not "coloured": a function that
does I/O is called like any other function, and a function that calls it does not change its signature.

The other style, explicit futures and `await` everywhere, was considered and rejected. It makes every caller of an
asynchronous function asynchronous too, all the way up, and it spreads the plumbing of concurrency through code that
does not care about it. In hecate, concurrency is explicit only where you want it: `fork`, `join`, `select`,
`deadline`, channels and locks.

Calling a suspending operation outside a coroutine that the reactor manages raises `NonYieldableContextError` at once.
Nothing ever blocks the reactor thread silently.

## Suspension points

Because suspension is invisible in the code, the list of calls that may suspend is fixed and documented. A
[suspension point](../reference/glossary.md#concurrency) is:

- every I/O operation: network, file system, processes, signals, name resolution, `offload`;
- `join`, `select`, `sleep`, `scope`, `deadline` and `shield`;
- the operations of channels, semaphores, mutexes, monitors and conditions that wait.

Nothing else suspends. `fork` and `detach` start a computation without suspending. A pure computation, however long,
never suspends: it holds the thread until it ends. The reference marks each suspending function with
`---@async`, and a test of the reactor checks that the marks match what the functions do.

Some places cannot suspend at all, because Lua cannot yield across them: the comparator of `table.sort`, the
replacement function of `string.gsub`, metamethods called from C, a module being loaded by `require`. A suspending
call there raises `NonYieldableContextError` with an explanation, instead of Lua's generic "attempt to yield across a
C-call boundary".

## Shared state between suspension points

Coroutines run one at a time, so the code between two suspension points runs without interruption. That is the
reason a reactor needs no lock for most state. It is also the trap: state can change *across* any suspension point.
A read-modify-write sequence that calls a database in the middle can interleave with the same sequence in another
request.

The framework therefore discourages module-level mutable state. State that belongs to a request lives in the request,
or in a scoped service of the [container](../reference/glossary.md#object-model-and-architecture). When state must be
shared, a [mutex](../reference/glossary.md#concurrency) protects the sequence that spans a suspension point.

## Structured concurrency

Every forked computation belongs to a [scope](../reference/glossary.md#concurrency). The rules:

1. A scope does not end before all its computations have ended.
2. When a computation fails, its scope cancels the others and raises the failure. Errors go up.
3. When a scope is cancelled, every computation in it is cancelled. Cancellation goes down.
4. Work that must outlive its scope is started with `reactor.detach`, which places it in the application scope. The
   escape is visible in the code.

The HTTP server runs each request in a scope of its own. A computation forked while serving a request cannot outlive
the request unnoticed: the request is not finished until it has ended, and a shutdown cancels it once the grace period is over. Without
this rule, background work started by a request leaks, holds connections and fails where nobody looks.

The design follows the literature on structured concurrency: Sústrik (2016) and the *nursery* of Smith (2018). The
vocabulary follows Conway (`fork`, `join`) and Hoare (`select`, channels): see the
[glossary](../reference/glossary.md#concurrency).

## Cooperative cancellation

[Cancellation](../reference/glossary.md#concurrency) is a request, not an interruption. It is delivered as a
`CancellationError` raised at the next suspension point of the cancelled coroutine, and again at every later
suspension point of the cancelled scope, until the coroutine ends. A coroutine that never suspends is never
cancelled. A [deadline](../reference/glossary.md#concurrency) works the same way, with `DeadlineExceededError`.

Because the error is raised, the `<close>` variables of the coroutine close as it unwinds. Their cleanup runs, but it
cannot suspend while its scope is cancelled: each suspension would raise again. `reactor.shield(limit, fn)` runs
cleanup that must suspend (flushing a buffer, a closing handshake) out of reach of the cancellation, bounded by its
own deadline.

Cancellation and deadline errors are never turned into problem details by the kernel: they belong to the scope that
raised them.

## Values that follow a computation

Some values concern every computation of a request, such as a request id for the logs. Passing them through every
function is noise. The [ambient context](../reference/glossary.md#concurrency) (`reactor.with_ambient`,
`reactor.ambient`, ADR 0025) binds them for a computation and for what it forks, as they are when it forks. Bindings
are immutable. It is an exception to explicit passing, kept for cross-cutting values; `log.bind` uses it.

## Several cores: processes, not threads

One reactor uses one core. To use several, hecate runs several processes, each with its own reactor and nothing
shared: the [workers](../reference/glossary.md#concurrency) of [Multi-process serving](multi-process-serving.md).
Threads would need a Lua state each, a copy of every value that crosses, and native modules that are all
thread-safe.

The one exception is `reactor.offload`, for CPU-bound work: a self-contained function runs in a separate Lua state
on libuv's thread pool, and its arguments and results are copied. See
[Offload CPU-bound work to the thread pool](../how-to/offload-cpu-bound-work.md).

## Testing

A reactor can run on a virtual clock (`reactor.Reactor({ clock = "virtual" })`): time jumps to the next timer when
nothing is ready, so tests of deadlines and sleeps run at once and give the same result every time.

## See also

- [Concurrency](../how-to/concurrency.md)
- [The transport model](transport-model.md)
- [Deadlines and cancellation on streams](../how-to/deadlines-and-cancellation.md)
- Reference: [`hecate.reactor`](../reference/reactor/index.md)
