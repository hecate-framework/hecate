# `hecate-core`

> Object model (classes, traits, interfaces), error hierarchy, enumerations, value objects and Lua-version compatibility shims.

| | |
|---|---|
| Module | `hecate.core` |
| Rock | `hecate-core` |
| Layer | 0 — Foundation |
| Roadmap phase | 1 |
| Status | specified — no code yet |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | none |
| Used by | `cli`, `config`, `container`, `doc`, `hecate`, `http`, `json`, `kernel`, `log`, `migration`, `mongodb`, `mysql`, `net`, `openapi`, `orm`, `postgresql`, `query`, `reactor`, `redis`, `router`, `schema`, `security`, `sql`, `sqlite`, `sqlserver`, `template`, `test`, `websocket` |
| Native code | none |
| Specification | [object-model.md](../../docs/architecture/object-model.md) |
| Decisions | [ADR 0001](../../docs/adr/0001-lua-5.5-as-sole-target.md), [ADR 0004](../../docs/adr/0004-academic-vocabulary.md), [ADR 0007](../../docs/adr/0007-object-model.md) |
| Agent | [`pkg-core`](../../.claude/agents/pkg-core.md) |
| Repository | read-only mirror `hecate-framework/hecate-core`, generated from this directory (ADR 0017) |

## Responsibilities

- `class`, `trait`, `interface`, `finalise`: single inheritance, flat trait composition with explicit conflict resolution, conformance checks at finalisation
- inherited metamethods including `__close`, `__eq`, `__lt`, `__tostring`, `__call`
- introspection used by container, kernel, orm, doc (`name`, `superclass`, `traits`, `interfaces`, `is_instance_of`)
- `Error` hierarchy with cause chaining, stable `code`, context, optional traceback
- `enumeration` and `value_class` (frozen, structurally compared)
- `hecate.core.compat`: shims for functions differing between Lua versions

## Non-goals

- multiple inheritance
- runtime-enforced visibility (convention + linter only)
- any I/O

## Standards and references

- Schärli et al., *Traits: Composable Units of Behaviour* (2003)

## Public API

*To be filled during implementation: list every exported class and function with a one-line
description, linking to the generated reference.*

## Layout (once implemented)

```text
src/hecate/core/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
```
