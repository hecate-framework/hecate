# 0025 — Ambient context: `reactor.with_ambient` and `reactor.ambient`

- **Status:** Accepted
- **Date:** 2026-10-22
- **Deciders:** project owner (shape agreed on 2026-10-22, accepted in the review of #29)
- **Packages:** reactor, log, kernel
- **Amended:** 2026-10-25, owner decision (OQ-56): `local` is a reserved word of Lua, so the pair `with_local`/`local` became `with_ambient`/`ambient`.
- **Related:** [concurrency.md](../architecture/concurrency.md) ("Scopes"), OQ-55, ADR 0002

## Context

Request-scoped values (a request id, an authenticated principal, a deadline budget) must reach every
computation forked while serving a request, without being passed through each function. `reactor`
offers nothing for it: `hecate.reactor.internal.context` is the scheduler's own state, not an API.
`hecate.log` works around it with `Logger:with_context` and a `context_provider` option (OQ-55).

How other systems answer, for comparison:

| System | Mechanism | Inherited by child work |
|---|---|---|
| Go | `context.Context` passed explicitly | no, passed by hand |
| Java | `ThreadLocal`, SLF4J MDC; `ScopedValue` (JEP 429 and later) | `ScopedValue`: yes, by structured-concurrency children |
| Python | `contextvars` (PEP 567) | the context is copied when a task is created |
| Node.js | `AsyncLocalStorage` | follows the asynchronous call chain |
| .NET | `AsyncLocal<T>`, `ExecutionContext` | flows across `await`, copied into child work |
| Kotlin | `CoroutineContext` elements | children inherit and may override |
| Swift | `@TaskLocal` | child tasks inherit; a binding is scoped to a closure |
| Rust (tokio) | `task_local!` | a spawned task does not inherit |

`fork` and `join` are structured concurrency, so the closest models are Swift task-locals, Java's
`ScopedValue` and Kotlin's coroutine context: a binding belongs to a region of code and children see it.

## Options considered

1. **Explicit passing** (Go). Nothing to build; every function signature carries the context, and
   third-party code cannot log with a request id. Rejected for a framework whose logger is called from everywhere.
2. **Mutable per-task storage** (`set_local(key, value)`, Python and .NET style). Simple to call, but it raises
   the question whether a child's write is visible to its parent or to its siblings, and a forgotten reset leaks
   a value into the next request served by the same task.
3. **Immutable, scoped bindings** (`with_ambient(key, value, fn)`, Swift, Java `ScopedValue`). A binding exists
   exactly while `fn` runs and in the computations forked from it; nothing to clean up, no write visible
   outside its region.

## Decision

Option 3, as written:

- `reactor.with_ambient(key, value, fn, ...)` runs `fn(...)` with `key` bound to `value` for the running task and
  returns the results of `fn`. A nested binding of the same key shadows the outer one until `fn` returns.
  The binding is removed when `fn` returns or raises.
- `reactor.ambient(key)` returns the value bound to `key` in the running task, or `nil`.
- `fork` and `detach` give the new computation the bindings visible **at the moment of the call**, from the
  creator, not from the application scope. Later bindings of the creator are not seen by the child.
- Bindings are immutable. A value that must change is a table the owner mutates, on purpose and visibly.
- `key` is any non-nil value compared by identity or equality; a module-private table is recommended, so
  that two packages cannot collide on a name.
- Both functions raise `hecate.core.NonYieldableContextError` outside a managed coroutine, like the other
  primitives.
- The bindings of a task form a persistent linked list (a node per binding, pointing to its parent), so
  inheritance is O(1) and a lookup is O(depth of nesting).

Uses once accepted: `kernel` binds the request id around each request; `log` reads it through the
`context_provider` it already has (the workaround is then replaced by the default provider); `security`
may bind the principal.

## Consequences

- Easier: request context in logs without passing it; one mechanism for every package that needs it.
- Harder: a public `reactor` API to maintain; `concurrency.md` gains a section; a hidden channel of data
  between functions, which the documentation must present as an exception to explicit passing.
- Roadmap: a `reactor` follow-up item (specify in `concurrency.md`, implement, test inheritance across
  `fork`, `detach`, `scope`, cancellation); a `log` follow-up (default context provider).

## Verification

Unit tests in `packages/reactor`: shadowing, removal on return and on error, inheritance at `fork` and
`detach`, no visibility of a later binding, isolation between siblings, behaviour under cancellation and
with the virtual clock. A `log` test checks that a record logged by a forked computation carries the bound request id.
