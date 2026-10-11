# `hecate-container`

> Inversion-of-control container: bindings, lifetimes (singleton, scoped, transient), constructor injection, cycle detection at boot.

| | |
|---|---|
| Module | `hecate.container` |
| Rock | `hecate-container` |
| Layer | 3 — Framework |
| Roadmap phase | 2 |
| Status | specified — no code yet |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core) |
| Used by | `hecate`, `kernel` |
| Native code | none |
| Specification | [http-and-routing.md](../../docs/architecture/http-and-routing.md) |
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

*To be filled during implementation: list every exported class and function with a one-line
description, linking to the generated reference.*

## Layout (once implemented)

```text
src/hecate/container/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
```
