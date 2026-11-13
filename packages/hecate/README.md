# `hecate`

> Meta-rock `hecate`: depends on the standard edition and provides the `hecate` meta-module re-exporting the framework surface.

| | |
|---|---|
| Module | `hecate` |
| Rock | `hecate` |
| Layer | Meta |
| Roadmap phase | 3 |
| Status | in progress — re-exports the surface of `kernel`; the standard edition (the meta-rock and its dependencies) is a Phase 3 item |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`reactor`](../reactor), [`net`](../net), [`json`](../json), [`log`](../log), [`http`](../http), [`schema`](../schema), [`router`](../router), [`container`](../container), [`config`](../config), [`kernel`](../kernel), [`openapi`](../openapi) |
| Used by | — |
| Native code | none |
| Specification | [overview.md](../../docs/architecture/overview.md) |
| Decisions | [ADR 0005](../../docs/adr/0005-single-brand-monorepo-lockstep-versioning.md) |
| Agent | [`pkg-hecate`](../../.claude/agents/pkg-hecate.md) |
| Repository | built from the monorepo (no mirror, ADR 0017) |

## Responsibilities

- single dependency for typical applications
- `require "hecate"` gives the application, controllers, routes, results and problem details; classes come from `hecate.core` and schemas from `hecate.schema` ([OQ-57](../../docs/open-questions.md))

## Non-goals

- code of its own beyond re-exports

## Standards and references

- —

## Public API

`require "hecate"` returns a table of re-exports: each name is the same value as in its source module,
and nothing else is exposed. Classes are declared with `core.class` from `hecate.core`, and schemas are
built with `hecate.schema` ([OQ-57](../../docs/open-questions.md)): the meta-module re-exports neither.

| Name | Source | Description |
|---|---|---|
| `Application` | `hecate.kernel` | the composition root |
| `Controller` | `hecate.kernel` | the superclass of controllers |
| `routes` | `hecate.kernel` | creates a route module (`hecate.routes "health"`) |
| `respond` | `hecate.kernel` | answers with a status and a value (`hecate.respond(201, user)`) |
| `problem` | `hecate.kernel` | problem classes (`hecate.problem.NotFound`) and `hecate.problem.define` |
| `load_configuration` | `hecate.kernel` | loads the configuration, wrapping secrets with `hecate.log.Secret` |
| `RouteDeclarationError`, `ModuleError`, `SupervisorError` | `hecate.kernel` | the errors of the kernel |

Two type names, for LuaLS annotations only (no value): `hecate.Controller`, a class deriving from
`hecate.kernel.Controller` (`---@class UserController : hecate.Controller`; a LuaLS alias cannot be a
superclass), and `hecate.Request`, an alias of `hecate.kernel.Request` (`---@param request hecate.Request`).

## Layout

```text
src/hecate/init.lua   public entry point (re-exports only)
tests/unit/           the re-export completeness test
```
