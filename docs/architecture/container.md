# Container (`hecate.container`)

Package: `container` (layer 3, Framework). Status: implemented. Decisions:
[ADR 0007](../adr/0007-object-model.md) (object model, which services build on),
[ADR 0018](../adr/0018-error-signalling.md) (errors), [ADR 0025](../adr/0025-ambient-context.md) (ambient
context). Undecided points are open questions OQ-104 to OQ-109 (OQ-106 is resolved) in [open-questions.md](../open-questions.md); each
statement below that depends on one says so. The package depends on `core` only: it knows nothing of `reactor`,
`http` or `kernel`.

Standards. Fowler, *Inversion of Control Containers and the Dependency Injection pattern* (2004): sections
"Forms of Dependency Injection" (constructor injection) and "Service Locator vs Dependency Injection" (the
locator is rejected here). Seemann, *Dependency Injection in .NET* (2011), section 3.2 "Composition Root": the
object graph is composed in one place, at the entry point of the application (the `Application` of
[http-and-routing.md](http-and-routing.md) is that place), and resolved from there.

## Scope and non-goals

A **container** holds **bindings** (a key, a way to build a **service**, a **lifetime**, the keys of the
services it needs), validates the whole graph at boot, and resolves services by constructor injection.

Non-goals, on purpose:

- **Service location from arbitrary code.** There is no global container, no module-level `resolve`, and no
  way to reach the container from a service unless the composition root passes it explicitly (which it should
  not). A service receives its dependencies in its constructor and nothing else. Only the composition root and
  the `kernel` call `resolve`.
- Setter, property or method injection; injection by reflection of parameter names; auto-wiring by type.
- Optional dependencies, several bindings under one key (collections of implementations), conditional
  bindings, decorators and interception, lazy proxies, named child containers.
- Constructors that suspend. A constructor and a factory run to completion without yielding (see
  "Construction"); opening a connection belongs to an explicit start step owned by the `kernel` (OQ-107).
- Configuration of the container from files, binding after validation, and any cross-process sharing:
  workers are processes (concurrency.md), each has its own container and its own singletons.

## Keys

A binding is registered under a **key**, which is either a **name** (a non-empty string, such as `"users"`) or
an **interface** (a value made by `core.interface`). Both are used the same way: `bind`, `requires`, `resolve`
accept either. Keys compare by identity (strings by value, interfaces by reference). A key has at most one
binding; `bind` on a key that is bound raises `DuplicateBindingError` (use `override`, below).

When the key is an interface, the product must conform to it: for a class definition the check happens at
`validate` (`core.implements`, a `core.ConformanceError` listed among the problems), for a factory definition
at the first construction, because the class of the product is unknown earlier. A name key carries no check.

## Definitions

```lua
local container = require("hecate.container")
local c = container.Container()

c:bind("clock", SystemClock, { lifetime = "singleton" })
c:bind("users", UserService, { lifetime = "scoped", requires = { "clock", UserRepository } })
c:bind(UserRepository, function(clock) return PgUserRepository(clock) end,
       { lifetime = "scoped", requires = { "clock" } })
```

`bind(key, definition, options?) → Container` (chainable). The `definition` is a finalised class, constructed
as `definition(dependency1, dependency2, ...)`, or a function (a **factory**), called with the same arguments.
The arguments are the resolved services of `options.requires`, in order. `options.lifetime` is
**required**: there is no default, so that the sharing of every service is stated where it is bound (owner decision
on OQ-104 (a); omitting it raises `core.ArgumentError` naming the three lifetimes). Dependencies are declared explicitly, never inferred (Fowler, "Forms of
Dependency Injection": constructor injection makes them visible in one place). An argument error (`key` neither
a non-empty string nor an interface, `definition` neither a class nor a function, missing or unknown lifetime, `requires`
not a list of keys) raises `core.ArgumentError`.

`hecate.container.Lifetime` is a `core.enumeration` with `singleton`, `scoped`, `transient`; options accept the
member or its name.

## Lifetimes

| Lifetime | An instance lives | Created |
|---|---|---|
| `singleton` | as long as the container (the process) | at first resolution, then shared by everyone |
| `scoped` | as long as one **service scope** | at first resolution inside that service scope, then shared inside it |
| `transient` | for the caller only; closed by its owner if it defines `__close` ("Disposal") | at every resolution, never shared, never cached |

A **service scope** (`container.ServiceScope`) is made by `container:open_scope()`. The `kernel` opens one per
request, and closes it when the request's reactor scope ends; `hecate.container` does not itself depend on the
reactor, so the link between the two is the kernel's, not the container's (OQ-105). The service scope is an
ordinary value: every computation forked during the request receives the same one when the kernel passes it,
typically through the ambient context (ADR 0025, key owned by the kernel), so a scoped service is **shared
across `fork`**, not duplicated per computation. A computation forked outside any request (`detach`) has no
service scope unless one is passed to it; asking the container for a scoped service without one fails (below).

Resolution entry points:

- `Container:resolve(key)` resolves from the root: `singleton` and `transient` services whose transitive
  dependencies are all `singleton` or `transient` (**root-resolvable**). Asking for a service that needs a
  scoped one raises `LifetimeError` (a programming error: the call has no service scope). It also raises
  `LifetimeError` for a closable transient that no singleton owns (see "Disposal").
- `ServiceScope:resolve(key)` resolves any service; scoped instances are cached in this service scope, singleton
  instances in the container.

`resolve` returns the service; it never returns `nil` (ADR 0018: failure raises). A key that is not bound
raises `MissingBindingError`, at request time only if the container was not validated (see below).

### Disposal

A service whose instance defines `__close` (`core` supports `__close`; there is no separate interface) is closed by
its owner, in reverse order of creation, each close attempted even if one fails (the first error is raised after all
were attempted, the others attached as `context.suppressed`):

- a **scoped** service is owned by the service scope that created it and closed when that scope closes;
- a **singleton** is owned by the container and closed when the container closes;
- a **closable transient** (a class with `__close`, or a factory whose product has one) is owned by the service scope
  that resolved it, tracked in the same list as the scoped services and closed with them, so the order of creation
  is the order of the whole list. This includes a transient dependency of a transient or of a scoped service resolved in
  that scope. A transient without `__close` is never tracked: it costs no memory. A closable transient created while a
  singleton is being constructed (a dependency of the singleton, even when the singleton is resolved inside a service
  scope) is owned by the container and closed with it, after the singleton that received it.

Owner decision on OQ-106 (2026-11-08). A scope that owns a transient closes it: the caller does not close it itself
(no `<close>` on it); the memory of a long-lived scope grows with the closable transients it resolved, which is the
price of owning them.

**Root resolution.** `Container:resolve(key)` has no service scope. When it would create a closable transient that no
singleton owns, that is the requested key itself or a transient dependency of it (not a dependency of a singleton it
builds, which the container owns), it raises `LifetimeError` with `context.key` (the requested key),
`context.dependency` (the closable transient) and `context.path`, and a message that says to resolve it through a
`ServiceScope` made by `container:open_scope()`. For a class definition, closability is known from the class, so the
error is raised before that class is constructed. For a factory it is known only after construction: the product is
closed at once, together, in reverse order of creation, with every other closable transient built in that same call,
and then the error is raised; nothing stays tracked. An error of such a close is attached to the `LifetimeError` as
`context.suppressed`.

`ServiceScope:release(instance)` closes a transient that the scope tracks now, instead of at the close of the scope,
and stops tracking it; it returns nothing, and a close error propagates as it is. An `instance` that is neither a table
nor a userdata raises `core.ArgumentError`; one that this scope does not track (never resolved here, scoped, owned by a
singleton, already released, or the scope is closed) raises `ContainerError`, so a second `release` of the same instance
is an error, and the scope does not close a released instance again.

`ServiceScope` and `Container` themselves support `<close>` and `:close()`; closing is idempotent. A closed service
scope or container refuses further `resolve` with `ContainerError`. Closing runs in the caller's computation, so when
the request is cancelled the kernel closes the service scope under `reactor.shield` (concurrency.md, rule 4, OQ-23) if
any `__close` suspends.

## Boot validation

`Container:validate()` checks the whole graph without constructing anything, and **freezes** the container:
after it, `bind` and `override` raise `ContainerError`, and `resolve` and `open_scope` are allowed only after it
(before it they raise `ContainerError`; there is no lazy validation). The `kernel` calls it at step 2 of the boot
sequence (overview.md); a failure aborts the boot with the diagnostic, as every failure of steps 1 to 5.

It detects, for every binding:

1. **Missing bindings**: a key in `requires` that is not bound. `MissingBindingError`, with `context.key`
   (the missing key) and `context.path` (the chain of keys that led to it, from the binding being checked).
2. **Cycles**: a chain of `requires` that returns to a key already on it (depth-first search with a
   visiting set). `CycleError`, with `context.path` listing the keys in order and the first key repeated at the
   end (`a -> b -> c -> a`). A binding that requires its own key is a cycle of length one. There is no lazy
   resolution to break a cycle; the cure is to restructure.
3. **Lifetime violations**: a service must not outlive what it depends on. The only rejected combination is a
   `singleton` that depends, directly or through `transient` services, on a `scoped` one: a request-bound
   object would be kept alive by a process-wide one (the "captive dependency", Seemann). A `transient` may
   depend on anything and be depended on by anything; a `scoped` service may depend on `singleton` and `scoped`
   services. `LifetimeError`, with `context.key` (the singleton), `context.dependency` (the scoped service)
   and `context.path`. A `singleton` that depends on a `transient` is accepted, with a **warning** (owner decision
   on OQ-104 (b)): the transient is built once and lives as long as the process. Only direct dependencies are
   reported (a singleton in between is checked on its own, so nothing is reported twice). A warning is a plain table
   `{ code = "singleton_over_transient", key, dependency, path, message }` (keys rendered as in the errors); it never
   fails the validation. `validate` returns the container and the list of warnings (the same list on a later call);
   the package has no logger, the `kernel` reports them.
4. **Conformance**: a class bound under an interface key that does not implement it (`core.ConformanceError`).

`validate` collects every problem, not only the first, and raises one `GraphError` (a `ContainerError`) whose
message states the count and the first problem and whose `context.problems` is the list of the individual error
instances above, in the order of binding. It is deterministic: bindings are checked in registration order (OQ-108 records the aggregation choice).

**Invariant: no resolution failure can happen at request time for a validated graph.** After `validate`
succeeds, every `resolve` of a bound key from a service scope, and of a root-resolvable key from the root,
finds all its dependencies, meets no cycle and violates no lifetime rule; the structural errors above cannot
be raised. What can still be raised is a failure inside user code: a constructor or factory that raises, which is
wrapped in `ConstructionError` (below), and the conformance check of a factory product (above), both being
defects of the service rather than of the graph. The only structural errors left at request time are the call of
`Container:resolve` for a service that needs a scoped one, or that creates a closable transient no singleton owns, which are mistakes of the caller and is documented as
such; the kernel never makes it.

## Construction

- A class definition is called `Class(...)`; a factory is called with the same arguments. Both run in the
  computation that resolves, without yielding: they must not suspend (OQ-107). Because they cannot yield, two
  computations never create the same singleton or scoped service twice, and no lock is needed.
- A re-entrant resolution of a key that is being constructed (possible only through a factory that captured the
  container, which is discouraged) raises `CycleError`, a second line of defence behind validation.
- An error raised by a constructor or factory is wrapped: `ConstructionError` with `context.key`,
  `context.path` and the original error as `cause`. The exception is `core.CancellationError` and
  `core.DeadlineExceededError`, which propagate unchanged so cancellation keeps its meaning (concurrency.md).
- A failed construction caches nothing: a later resolution tries again.

## Overrides for tests

`Container:override(key, definition, options?)` replaces the binding of `key`; it exists for tests and for the
composition root of a test application (testing.md, "Fixtures": container overrides). It raises
`MissingBindingError` when `key` is not already bound (a misspelt key must not silently create a service), and
`ContainerError` after `validate`. When `options` is omitted, the lifetime and `requires` of the replaced binding are kept; when it is given,
it replaces both (defaults as for `bind`). The replaced definition is discarded and the new graph is validated as a whole by `validate`, so an
override cannot introduce a cycle or a lifetime violation unnoticed. `Container:override_instance(key, value)`
binds an existing object as a `singleton` with no dependencies, the usual way to inject a fake.

An override is an ordinary binding in every other respect. There is no "test mode": the same method works in
production, and the same rules apply (OQ-104 (c): the owner chose no test mode; `override` is already refused after `validate`). Without `options`
the lifetime and `requires` of the replaced binding are kept; with `options`, the lifetime is required as for `bind`.

## Errors

All extend `hecate.core.Error` through `core.ConfigurationError`, since each means the composition is wrong
(ADR 0018: stable `code`, message, `cause`, `context`). Defined in `hecate.container`:

| Class | Superclass | Raised when | `context` |
|---|---|---|---|
| `ContainerError` | `core.ConfigurationError` | base class; also a use in the wrong state (before `validate`, after it for `bind`, after `close`) | varies |
| `DuplicateBindingError` | `ContainerError` | `bind` on a bound key | `key` |
| `MissingBindingError` | `ContainerError` | a required or requested key has no binding; `override` of an unbound key | `key`, `path` |
| `CycleError` | `ContainerError` | the dependency graph has a cycle | `path` |
| `LifetimeError` | `ContainerError` | a singleton depends on a scoped service; a scoped service is requested from the root; the root would create a closable transient that no singleton owns ("Disposal") | `key`, `dependency`, `path` (`suppressed` for the last case, if closing failed) |
| `GraphError` | `ContainerError` | `validate` found one or more problems | `problems` |
| `ConstructionError` | `ContainerError` | a constructor or factory raised | `key`, `path`; `cause` |

Wrong arguments raise `core.ArgumentError`; a conformance failure is the `core.ConformanceError` of `core`.
The state error of OQ-77 (a state error class missing from `core`) is the reason `ContainerError` stands for
wrong-state use, and the choice is revisited when `core` gets it. In messages and context, keys are rendered
by name, an interface by its `core.name`, never by address.

## Public API summary

`hecate.container`: `Container` (`bind`, `override`, `override_instance`, `validate`, `resolve`, `open_scope`,
`close`), `ServiceScope` (`resolve`, `release`, `close`), `Lifetime`, and the error classes above. Every function carries
LuaLS annotations; none is `---@async`, because nothing here suspends.

## Tests required by the invariants

Graph validation: each of missing binding, cycle (lengths one, two, many), lifetime violation (direct, through
a transient), interface conformance, several problems at once, registration-order determinism, freezing after
`validate`, `resolve` before it. Scoped lifetime: one instance per service scope, shared by computations forked
in the same request (with a virtual-clock reactor in an integration test, outside the package), distinct across
service scopes, disposal order (scoped and closable transients mixed, a singleton-owned transient, root refusal for a class and for a factory, `release`). Overrides: unbound key, after validation, revalidation catches a violation.
Errors: wrapping, cancellation not wrapped, the property that a validated graph yields no structural error
(a randomised graph test).
