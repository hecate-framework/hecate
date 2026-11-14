---
description: Bind services in a container, choose singleton, scoped or transient lifetimes, validate the graph at boot, resolve by constructor injection, close services and replace them in tests with hecate.container.
hecate: "0.x"
lua: "5.5"
order: 14
---

# Use the container

This guide shows how to build the objects of an application with `hecate.container`. It is written for hecate 0.x
and Lua 5.5.

A [container](../reference/glossary.md#object-model-and-architecture) is an object that resolves and constructs
dependencies. Each object it builds is a [service](../reference/glossary.md#object-model-and-architecture). You list
the services and what each one needs in one place, the
[composition root](../reference/glossary.md#object-model-and-architecture). The container checks the whole graph
before anything runs, then constructs services when they are asked for.

`hecate.container` depends only on `hecate.core`. It needs no native module, and it never suspends.

## Bind, validate, resolve

A container is used in three steps: bind the services, validate the graph once, then resolve services.

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

A service never asks the container for anything: it receives its dependencies in its constructor. There is no
global container and no way to reach one from a service. Only the composition root and the kernel call `resolve`.

## Bind a service

`bind(key, definition, options?)` registers one service. It returns the container, so calls chain.

- The **key** is a non-empty string (a name) or an [interface](../reference/glossary.md#object-model-and-architecture)
  made by `core.interface`. A key has one binding: binding it twice raises `DuplicateBindingError`. `has(key)` tells
  whether a key is bound, without building anything.
- The **definition** is a finalised class, called as `Class(dependency1, dependency2, ...)`. It can also be a
  function (a factory), called with the same arguments.
- `requires` lists the keys of the dependencies, in the order of the constructor arguments. Dependencies are
  declared, never guessed from parameter names.
- `lifetime` is `"singleton"`, `"scoped"` or `"transient"` (or a member of `container.Lifetime`). It is required:
  binding without it raises `ArgumentError`. So what a service shares is always written where it is bound.

A definition must run to completion without suspending. While one suspends, resolving the same key from another
computation raises `ContainerError`.

When the key is an interface, a class definition must implement it; `validate` reports it otherwise. A factory
product is checked when it is first built.

## Choose a lifetime

| Lifetime | An instance lives | Created |
|---|---|---|
| `singleton` | as long as the container | at the first resolution, then shared |
| `scoped` | as long as one service scope | at the first resolution in that scope, then shared inside it |
| `transient` | for the caller only (closed by its scope if it defines `__close`) | at every resolution, never cached |

### Open a service scope

A [service scope](../reference/glossary.md#object-model-and-architecture) is the region in which a `scoped` service
has one instance. `container:open_scope()` makes one, and the kernel opens one per request. It is not a reactor
scope.

A service scope is an ordinary value. Every computation that receives it sees the same scoped instances, so a scoped
service is shared across `fork`, not copied.

Close the scope when the request ends: call `scope:close()`, or hold it in a `<close>` variable as the example does.

### Resolve from the container or from a scope

- `scope:resolve(key)` builds any service.
- `container:resolve(key)` builds singletons, and transients whose dependencies are all singletons or transients.

`container:resolve` has no service scope. Two cases raise `LifetimeError` there, before anything is constructed:

- a service that needs a scoped one;
- a transient that defines `__close` and that no singleton owns. Resolve it with `scope:resolve`.

## Validate at boot

`container:validate()` checks every binding without constructing anything. It reports:

- a **missing binding**: a required key that is not bound (`MissingBindingError`);
- a **cycle**: `a -> b -> c -> a`, the shortest case being a binding that requires itself (`CycleError`);
- a **lifetime violation**: a singleton that depends on a scoped service, directly or through transients
  (`LifetimeError`). It would keep a request-bound object alive for the whole process;
- a class that does not implement its **interface** key (`core.ConformanceError`).

There is no lazy resolution to break a cycle: restructure the services instead.

`validate` collects every problem and raises one `GraphError`. `err.context.problems` lists them in the order of
binding. A validated graph raises none of these at request time: what can still fail is the code of a constructor.

Validation also freezes the container. Afterwards, `bind` and `override` raise `core.StateError`. Before it has
succeeded, `resolve` and `open_scope` raise `core.StateError`.

### Read the warnings

`validate` returns the container and a list of **warnings**, which never fail it.

A singleton that directly depends on a transient gets a warning with `code = "singleton_over_transient"`, `key`,
`dependency`, `path` and a `message`. That transient is built once and lives as long as the process.

The container has no logger; the kernel reports the warnings.

## Close services

A service whose instance defines `__close` is closed by its owner, in reverse order of creation:

- a scoped service, and a closable transient, when the service scope that resolved them closes;
- a singleton, and a closable transient it received, when the container closes.

A transient without `__close` is never tracked.

Every close is attempted. The first error is raised afterwards, and the others are in `context.suppressed`. Closing
is idempotent, and a closed scope or container refuses `resolve`.

### Release a transient early

A scope that owns a transient closes it, so do not put a `<close>` on it yourself. To close it earlier, call
`scope:release(instance)`. It closes the instance once and stops tracking it; a close error propagates as it is.

Releasing an instance the scope does not track raises `ContainerError`, and so does releasing it a second time.

A long-lived scope keeps the closable transients it resolved until it closes or you release them.

### Shared instances

An owner closes an instance once, however many times a factory returned it. The instance of a singleton, returned
again by a transient factory, stays the container's.

When a singleton fails to build, the closable transients built for it are closed at once.

## Handle construction errors

An error raised by a constructor or a factory becomes a `ConstructionError`:

- its `cause` is the original error;
- `context.key` says which service failed;
- `context.path` says through which chain it was reached.

`CancellationError` and `DeadlineExceededError` pass through unchanged.

A constructor that returns `nil` raises `ConstructionError` too. A factory product that does not implement its
interface key raises `core.ConformanceError`, with the same `context.path`, after being closed if it defines
`__close`.

A failed construction caches nothing: the next resolution tries again.

## Replace a service in a test

`override(key, definition, options?)` replaces a binding before `validate`.

- Without `options`, it keeps the lifetime and `requires` of the replaced binding.
- With `options`, `lifetime` is required, as for `bind`.

A key that is not bound raises `MissingBindingError`, so a misspelt key cannot create a service by accident.

`override_with_instance(key, value)` binds an existing object as a singleton without dependencies. It is the usual
way to inject a fake.

- The key must be bound.
- For an interface key, the value must implement it. A fake that does not raises `core.ConformanceError` at the call.
- The container never closes that object, even one that defines `__close`: you built it, so you close it.

The new graph is validated as a whole. An override cannot add a cycle or a captive dependency unnoticed.

## Know the errors

All container errors extend `core.ConfigurationError`:

- `ContainerError`;
- `DuplicateBindingError`;
- `MissingBindingError`;
- `CycleError`;
- `LifetimeError`;
- `GraphError`;
- `ConstructionError`.

A wrong argument raises `core.ArgumentError`. A use in the wrong state raises `core.StateError`: a use before
`validate`, `bind` or `override` after it, and any use after `close`.

In messages and `context`, an interface is shown by its name.

## See also

- [Concurrency](concurrency.md): scoped services as a way to avoid shared state.
- Reference: [`hecate.container`](../reference/container/index.md)
