# Container (`hecate.container`)

Package: `container` (layer 3, Framework). Status: implemented. Decisions:
[ADR 0007](../adr/0007-object-model.md) (object model, which services build on),
[ADR 0018](../adr/0018-error-signalling.md) (errors), [ADR 0025](../adr/0025-ambient-context.md) (ambient
context). Undecided points are open questions OQ-98 to OQ-102 in [open-questions.md](../open-questions.md); each
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
  "Construction"); opening a connection belongs to an explicit start step owned by the `kernel` (OQ-101).
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
The arguments are the resolved services of `options.requires`, in order. `options.lifetime` defaults to
`"transient"`, the most conservative choice because it shares no state (OQ-98 asks the owner whether the
default should instead be required). Dependencies are declared explicitly, never inferred (Fowler, "Forms of
Dependency Injection": constructor injection makes them visible in one place). An argument error (`key` neither
a non-empty string nor an interface, `definition` neither a class nor a function, unknown lifetime, `requires`
not a list of keys) raises `core.ArgumentError`.

`hecate.container.Lifetime` is a `core.enumeration` with `singleton`, `scoped`, `transient`; options accept the
member or its name.

## Lifetimes

| Lifetime | An instance lives | Created |
|---|---|---|
| `singleton` | as long as the container (the process) | at first resolution, then shared by everyone |
| `scoped` | as long as one **service scope** | at first resolution inside that service scope, then shared inside it |
| `transient` | for the caller only | at every resolution, never shared, never cached |

A **service scope** (`container.ServiceScope`) is made by `container:open_scope()`. The `kernel` opens one per
request, and closes it when the request's reactor scope ends; `hecate.container` does not itself depend on the
reactor, so the link between the two is the kernel's, not the container's (OQ-99). The service scope is an
ordinary value: every computation forked during the request receives the same one when the kernel passes it,
typically through the ambient context (ADR 0025, key owned by the kernel), so a scoped service is **shared
across `fork`**, not duplicated per computation. A computation forked outside any request (`detach`) has no
service scope unless one is passed to it; asking the container for a scoped service without one fails (below).

Resolution entry points:

- `Container:resolve(key)` resolves from the root: `singleton` and `transient` services whose transitive
  dependencies are all `singleton` or `transient` (**root-resolvable**). Asking for a service that needs a
  scoped one raises `LifetimeError` (a programming error: the call has no service scope).
- `ServiceScope:resolve(key)` resolves any service; scoped instances are cached in this service scope, singleton
  instances in the container.

`resolve` returns the service; it never returns `nil` (ADR 0018: failure raises). A key that is not bound
raises `MissingBindingError`, at request time only if the container was not validated (see below).

### Disposal

A service whose class defines `__close` (`core` supports `__close`) is closed by its owner: a scoped service when
its service scope closes, a singleton when the container closes, both in reverse order of creation, each close
attempted even if one fails (the first error is raised after all were attempted, the others attached as
`context.suppressed`). `ServiceScope` and `Container` themselves support `<close>` and `:close()`; closing is
idempotent. A transient service is **not** tracked: its consumer owns it (OQ-100). A closed service scope or
container refuses further `resolve` with `ContainerError`. Closing runs in the caller's computation, so when the
request is cancelled the kernel closes the service scope under `reactor.shield` (concurrency.md, rule 4,
OQ-23) if any `__close` suspends.

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
   and `context.path`. A `singleton` that depends on a `transient` is accepted: the transient is built once and
   kept (OQ-98 asks whether a warning is wanted).
4. **Conformance**: a class bound under an interface key that does not implement it (`core.ConformanceError`).

`validate` collects every problem, not only the first, and raises one `GraphError` (a `ContainerError`) whose
message states the count and the first problem and whose `context.problems` is the list of the individual error
instances above, in the order of binding. It is deterministic: bindings are checked in registration order (OQ-102 records the aggregation choice).

**Invariant: no resolution failure can happen at request time for a validated graph.** After `validate`
succeeds, every `resolve` of a bound key from a service scope, and of a root-resolvable key from the root,
finds all its dependencies, meets no cycle and violates no lifetime rule; the structural errors above cannot
be raised. What can still be raised is a failure inside user code: a constructor or factory that raises, which is
wrapped in `ConstructionError` (below), and the conformance check of a factory product (above), both being
defects of the service rather than of the graph. The only structural error left at request time is the call of
`Container:resolve` for a service that needs a scoped one, which is a mistake of the caller and is documented as
such; the kernel never makes it.

## Construction

- A class definition is called `Class(...)`; a factory is called with the same arguments. Both run in the
  computation that resolves, without yielding: they must not suspend (OQ-101). Because they cannot yield, two
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
production, and the same rules apply (OQ-98 notes the option of refusing it once a container is started).

## Errors

All extend `hecate.core.Error` through `core.ConfigurationError`, since each means the composition is wrong
(ADR 0018: stable `code`, message, `cause`, `context`). Defined in `hecate.container`:

| Class | Superclass | Raised when | `context` |
|---|---|---|---|
| `ContainerError` | `core.ConfigurationError` | base class; also a use in the wrong state (before `validate`, after it for `bind`, after `close`) | varies |
| `DuplicateBindingError` | `ContainerError` | `bind` on a bound key | `key` |
| `MissingBindingError` | `ContainerError` | a required or requested key has no binding; `override` of an unbound key | `key`, `path` |
| `CycleError` | `ContainerError` | the dependency graph has a cycle | `path` |
| `LifetimeError` | `ContainerError` | a singleton depends on a scoped service; a scoped service is requested from the root | `key`, `dependency`, `path` |
| `GraphError` | `ContainerError` | `validate` found one or more problems | `problems` |
| `ConstructionError` | `ContainerError` | a constructor or factory raised | `key`, `path`; `cause` |

Wrong arguments raise `core.ArgumentError`; a conformance failure is the `core.ConformanceError` of `core`.
The state error of OQ-77 (a state error class missing from `core`) is the reason `ContainerError` stands for
wrong-state use, and the choice is revisited when `core` gets it. In messages and context, keys are rendered
by name, an interface by its `core.name`, never by address.

## Public API summary

`hecate.container`: `Container` (`bind`, `override`, `override_instance`, `validate`, `resolve`, `open_scope`,
`close`), `ServiceScope` (`resolve`, `close`), `Lifetime`, and the error classes above. Every function carries
LuaLS annotations; none is `---@async`, because nothing here suspends.

## Tests required by the invariants

Graph validation: each of missing binding, cycle (lengths one, two, many), lifetime violation (direct, through
a transient), interface conformance, several problems at once, registration-order determinism, freezing after
`validate`, `resolve` before it. Scoped lifetime: one instance per service scope, shared by computations forked
in the same request (with a virtual-clock reactor in an integration test, outside the package), distinct across
service scopes, disposal order. Overrides: unbound key, after validation, revalidation catches a violation.
Errors: wrapping, cancellation not wrapped, the property that a validated graph yields no structural error
(a randomised graph test).
