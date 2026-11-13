---
description: Bind services in a container, choose singleton, scoped or transient lifetimes, validate the graph at boot, resolve by constructor injection, close services and replace them in tests with hecate.container.
hecate: "0.x"
lua: "5.5"
order: 14
---

# Use the container

`hecate.container` builds the objects of an application from declared dependencies. You list the services and what
each one needs in one place, the composition root; the container checks the whole graph before anything runs, then
constructs services when they are asked for. It depends only on `hecate.core`, needs no native module, and never
suspends.

A service never asks the container for anything: it receives its dependencies in its constructor. There is no global
container and no way to reach one from a service. Only the composition root and the kernel call `resolve`.

## Bind, validate, resolve

<!-- example: packages/container/examples/hecate.container.Container.lua -->
```lua
-- Bind services, validate the graph at boot, then resolve them: a singleton
-- is shared, a scoped service lives in one service scope (one per request), a
-- transient is built for each caller.
local core = require("hecate.core")
local container = require("hecate.container")

local Clock = core.class("Clock")
function Clock:now() return 1700000000 end
core.finalise(Clock)

local Session = core.class("Session")
function Session:init(clock) self.opened_at = clock:now() end
function Session:__close() self.closed = true end
core.finalise(Session)

local c = container.Container()
c:bind("clock", Clock, { lifetime = "singleton" })
c:bind("session", Session, { lifetime = "scoped", requires = { "clock" } })
c:validate()

local session
do
  local request <close> = c:open_scope()
  session = request:resolve("session")
  print(session == request:resolve("session"))
  -- Prints: true
  print(c:open_scope():resolve("session") == session)
  -- Prints: false
  print(c:resolve("clock") == request:resolve("clock"))
  -- Prints: true
end
-- Closing the scope closes its scoped services.
print(session.closed)
-- Prints: true

-- A mistake in the composition is found at boot, with every problem at once.
local broken = container.Container()
broken:bind("a", function() end, { lifetime = "transient", requires = { "b" } })
broken:bind("b", function() end, { lifetime = "transient", requires = { "a", "missing" } })
local ok, err = pcall(function() broken:validate() end)
---@cast err hecate.container.GraphError
print(ok, err.context.problems[1].context.path[1], #err.context.problems)
-- Prints: false	a	2
```

`bind(key, definition, options?)` registers one service and returns the container, so calls chain.

- The **key** is a non-empty string (a name) or an interface made by `core.interface`. A key has one binding;
  binding it twice raises `DuplicateBindingError`. `has(key)` tells whether a key is bound, without building anything.
- The **definition** is a finalised class, called as `Class(dependency1, dependency2, ...)`, or a function (a
  factory) called with the same arguments. It must run to completion without suspending: while one suspends, resolving
  the same key from another computation raises `ContainerError`.
- `requires` lists the keys of the dependencies, in the order of the constructor arguments. Dependencies are declared,
  never guessed from parameter names.
- `lifetime` is `"singleton"`, `"scoped"` or `"transient"` (or a member of `container.Lifetime`). It is required:
  binding without it raises `ArgumentError`, so that what a service shares is always written where it is bound.

When the key is an interface, a class definition must implement it; `validate` reports it otherwise. A factory
product is checked when it is first built.

## Lifetimes

| Lifetime | An instance lives | Created |
|---|---|---|
| `singleton` | as long as the container | at the first resolution, then shared |
| `scoped` | as long as one service scope | at the first resolution in that scope, then shared inside it |
| `transient` | for the caller only (closed by its scope if it defines `__close`) | at every resolution, never cached |

A service scope is made by `container:open_scope()`; the kernel opens one per request. It is an ordinary value:
every computation that receives it sees the same scoped instances, so a scoped service is shared across `fork`, not
copied. Close the scope when the request ends (`scope:close()` or a `<close>` variable).

- `container:resolve(key)` builds singletons and transients whose dependencies are all singletons or transients. A
  service that needs a scoped one raises `LifetimeError`, before anything is constructed: the call has no service
  scope. So does a transient that defines `__close` and that no singleton owns: resolve it with `scope:resolve`.
- `scope:resolve(key)` builds any service.

## Validate at boot

`container:validate()` checks every binding without constructing anything, then freezes the container: `bind` and
`override` raise `ContainerError` afterwards, and `resolve` and `open_scope` raise it until validation has succeeded.
It reports:

- a **missing binding**: a required key that is not bound (`MissingBindingError`);
- a **cycle**: `a -> b -> c -> a`, with a binding that requires itself as the shortest case (`CycleError`). There is no
  lazy resolution to break a cycle; restructure instead;
- a **lifetime violation**: a singleton that depends on a scoped service, directly or through transients, which would
  keep a request-bound object alive for the whole process (`LifetimeError`);
- a class that does not implement its **interface** key (`core.ConformanceError`).

It collects every problem and raises one `GraphError`; `err.context.problems` lists them in the order of binding. A
validated graph raises none of these at request time: what can still fail is the code of a constructor.

`validate` also returns the container and a list of **warnings**, which never fail it: a singleton that directly
depends on a transient gets `code = "singleton_over_transient"`, with `key`, `dependency`, `path` and a `message`,
because that transient is built once and lives as long as the process. The container has no logger; the kernel
reports the warnings.

## Disposal

A service whose instance defines `__close` is closed by its owner, in reverse order of creation: a scoped service and
a closable transient when the service scope that resolved them closes, a singleton (and a closable transient it
received) when the container closes. A transient without `__close` is never tracked. Every close is attempted; the first
error is raised afterwards and the others are in `context.suppressed`. Closing is idempotent, and a closed scope or
container refuses `resolve`.

A scope that owns a transient closes it, so do not put a `<close>` on it yourself. To close it earlier, call
`scope:release(instance)`: it closes the instance once and stops tracking it (a close error propagates as it is);
releasing an instance the scope does not track, a second time included, raises `ContainerError`. A long-lived scope
keeps the closable transients it resolved until it closes or you release them.

An owner closes an instance once, however many times a factory returned it, and the instance of a singleton,
returned again by a transient factory, stays the container's. When a singleton fails to build, the closable
transients built for it are closed at once.

## Construction errors

An error raised by a constructor or factory becomes a `ConstructionError` whose `cause` is the original error and whose
`context.key` and `context.path` say which service and through which chain. `CancellationError` and
`DeadlineExceededError` pass through unchanged. A constructor that returns `nil` raises `ConstructionError` too, and a
factory product that does not implement its interface key raises `core.ConformanceError` (with the same `context.path`),
after being closed if it defines `__close`. A failed construction caches nothing; the next resolution tries again.

## Replace a service in a test

`override(key, definition, options?)` replaces a binding before `validate`; without `options` it keeps the lifetime and
`requires` of the replaced binding; with `options`, `lifetime` is required as for `bind`. A key that is not bound raises `MissingBindingError`, so a misspelt key cannot
create a service by accident. `override_with_instance(key, value)` binds an existing object as a singleton without
dependencies, the usual way to inject a fake. The key must be bound; for an interface key the value must implement it, and a fake that does not raises `core.ConformanceError` at the call. The container never closes that object, even one that defines `__close`: you built it, so you close it. The new graph is validated as a whole, so an override cannot add a cycle
or a captive dependency unnoticed.

## Errors

All container errors extend `core.ConfigurationError`: `ContainerError` (also a use in the wrong state),
`DuplicateBindingError`, `MissingBindingError`, `CycleError`, `LifetimeError`, `GraphError` and `ConstructionError`.
A wrong argument raises `core.ArgumentError`. In messages and `context`, an interface is shown by its name.
