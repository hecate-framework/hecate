# Agent context — `hecate.kernel`

You are working inside `packages/kernel`. Read the root `CLAUDE.md` first; this file adds
package-specific context. Specialist agent: `pkg-kernel`.

## Purpose

The application: feature modules, controllers, route modules, filters (chain of responsibility), problem details, lifecycle, workers and graceful shutdown.

## Read before changing anything

- Specification: `docs/architecture/http-and-routing.md`
- Decisions: `docs/adr/0003-transparent-structured-concurrency.md`, `docs/adr/0006-declarative-routes-as-runtime-data.md`, `docs/adr/0007-object-model.md`
- Glossary: `docs/glossary.md` · Coding standards: `docs/architecture/coding-standards.md`
- This package's `README.md` (scope, dependencies, status)

## Boundaries

- Allowed dependencies: `hecate.core`, `hecate.reactor`, `hecate.log`, `hecate.http`, `hecate.router`, `hecate.schema`, `hecate.container`, `hecate.config`, `hecate.json`.
  Anything else requires an ADR; `check-boundaries` fails otherwise.
- Native code: none.
- Out of scope: templating (later, `template`).
- If your task needs a change in another package, stop and describe the needed change
  instead of making it (unless the task explicitly spans packages).

## Invariants (must hold after every change)

- both declaration styles produce identical route tables
- nothing validated lazily at first request
- internal error messages are not exposed by default

## Test strategy

- end-to-end with in-process client
- boot failure diagnostics
- graceful shutdown under load

Plus, for every change: unit tests for public behaviour, LuaLS annotations on public API
(`---@async` on anything that may suspend), README "Public API" section updated.

## Known pitfalls

- filter ordering
- streaming responses and filters

## Standards

- RFC 9457 (problem details)
- RFC 9110 (content negotiation)
