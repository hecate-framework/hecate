# `hecate-kernel`

> The application: feature modules, controllers, route modules, filters (chain of responsibility), problem details, lifecycle, workers and graceful shutdown.

| | |
|---|---|
| Module | `hecate.kernel` |
| Rock | `hecate-kernel` |
| Layer | 3 — Framework |
| Roadmap phase | 2 |
| Status | specified — no code yet |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`reactor`](../reactor), [`log`](../log), [`http`](../http), [`router`](../router), [`schema`](../schema), [`container`](../container), [`config`](../config), [`json`](../json) |
| Used by | `cli`, `hecate`, `security`, `template`, `test` |
| Native code | none |
| Specification | [http-and-routing.md](../../docs/architecture/http-and-routing.md) |
| Decisions | [ADR 0003](../../docs/adr/0003-transparent-structured-concurrency.md), [ADR 0006](../../docs/adr/0006-declarative-routes-as-runtime-data.md), [ADR 0007](../../docs/adr/0007-object-model.md) |
| Agent | [`pkg-kernel`](../../.claude/agents/pkg-kernel.md) |
| Repository | read-only mirror `hecate-framework/hecate-kernel`, generated from this directory (ADR 0017) |

## Responsibilities

- `Application` (composition root), feature modules, `Controller` superclass, route modules
- boot sequence with full validation (overview.md)
- filters around actions; request scope (the reactor scope of a request) and the scoped lifetime of the container
- coercion/validation of inputs, serialisation of results, response validation in development/test
- problem details mapping of errors
- workers (multi-process) and graceful shutdown
- meta-module `hecate` re-exporting the framework surface

## Non-goals

- templating (later, `template`)

## Standards and references

- RFC 9457 (problem details)
- RFC 9110 (content negotiation)

## Public API

*To be filled during implementation: list every exported class and function with a one-line
description, linking to the generated reference.*

## Layout (once implemented)

```text
src/hecate/kernel/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
```
