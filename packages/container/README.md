# `hecate-container`

> Inversion-of-control container: bindings, lifetimes (singleton, scoped, transient), constructor injection, cycle detection at boot.

| | |
|---|---|
| Module | `hecate.container` |
| Rock | `hecate-container` |
| Layer | 3 — Framework |
| Roadmap phase | 2 |
| Status | alpha — implemented in Phase 2: bindings, lifetimes, boot validation, constructor injection, disposal, overrides |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core) |
| Used by | `hecate`, `kernel` |
| Native code | none |
| Specification | [container.md](../../docs/architecture/container.md), [http-and-routing.md](../../docs/architecture/http-and-routing.md) |
| Decisions | [ADR 0007](../../docs/adr/0007-object-model.md) |
| Agent | [`pkg-container`](../../.claude/agents/pkg-container.md) |
| Repository | read-only mirror `hecate-framework/hecate-container`, generated from this directory (ADR 0017) |

## Responsibilities

- bindings by name or interface
- lifetimes: singleton (per process), scoped (per reactor scope, e.g. request), transient
- graph validation at boot (missing bindings, cycles, lifetime violations)
- overrides for tests

## Non-goals

- service location from arbitrary code (anti-pattern)

## Standards and references

- Fowler, *Inversion of Control Containers and the Dependency Injection pattern* (2004)
- Seemann, composition root (2011)

## Public API

`local container = require("hecate.container")`. The guide is
[Use the container](../../website/en/how-to/use-the-container.md); the generated reference will list every annotation.
Nothing here suspends, so nothing is `---@async`.

- `container.Container()`: bindings, validation and resolution.
  - `bind(key, definition, options?)`: `key` is a name or an interface, `definition` a finalised class or a factory,
    `options.lifetime` (required) and `options.requires` (keys, in constructor order). Chainable.
  - `override(key, definition, options?)` and `override_with_instance(key, value)`: replace a bound key (tests); for an interface key the value must implement it, checked at the call (`core.ConformanceError`).
  - `validate()`: checks the whole graph, raises one `GraphError`, then freezes the container. Returns the container and a list of warnings (`code = "singleton_over_transient"`: a singleton directly depends on a transient); warnings never fail it, the kernel logs them.
  - `resolve(key)`: singletons and transients that need no scoped service, and no closable transient that a singleton does not own (`LifetimeError`). `open_scope()`: a `ServiceScope`.
  - `close()` (also `<close>`): closes the singletons that define `__close`.
- `container.ServiceScope`: `resolve(key)`, `release(instance)` (closes a tracked transient now) and `close()` (also `<close>`).
- `container.Lifetime`: enumeration `singleton`, `scoped`, `transient`.
- Errors, all `core.ConfigurationError`: `ContainerError`, `DuplicateBindingError`, `MissingBindingError`,
  `CycleError`, `LifetimeError`, `GraphError`, `ConstructionError`.

### Behaviour

- Dependencies are declared in `requires`, never inferred. A key has one binding.
- `validate` reports missing bindings, cycles, a singleton that depends on a scoped service (directly or through
  transients) and a class that does not implement its interface key; resolution is refused before it succeeds.
- Resolving from the container a service that needs a scoped one raises `LifetimeError` before constructing anything.
- A constructor error becomes `ConstructionError` (cancellation and deadline errors pass through); nothing is cached
  on failure.
- Services with `__close` are closed in reverse order of creation by their owner: scoped services and closable transients by the service scope that resolved them (a transient without `__close` is never tracked), singletons and the closable transients they received by the container. `Container:resolve` refuses a closable transient that no singleton owns (`LifetimeError`: resolve it through a service scope). Do not close a transient that a scope owns; use `scope:release(instance)` to close it early.
- `override_with_instance` requires the key to be bound, like `override`, and checks an interface key at the call.

## Layout

```text
src/hecate/container/   init.lua  container.lua  graph.lua  lifetime.lua  errors.lua
tests/unit/  examples/
```
