# Agent context — `hecate.cli`

You are working inside `packages/cli`. Read the root `CLAUDE.md` first; this file adds
package-specific context. Specialist agent: `pkg-cli`.

## Purpose

The `hecate` command: toolchains, projects, dependencies (LuaRocks), development server, tests, contracts, documentation, migrations, scaffolding, packaging.

## Read before changing anything

- Specification: `docs/architecture/cli-and-packaging.md`
- Decisions: `docs/adr/0009-project-manifest.md`, `docs/adr/0010-self-contained-cli-and-managed-toolchains.md`
- Glossary: `docs/glossary.md` · Coding standards: `docs/architecture/coding-standards.md`
- This package's `README.md` (scope, dependencies, status)

## Boundaries

- Allowed dependencies: `hecate.core`, `hecate.reactor`, `hecate.log`, `hecate.json`, `hecate.schema`, `hecate.kernel`, `hecate.test`, `hecate.doc`, `hecate.openapi`, `hecate.migration`.
  Anything else requires an ADR; `check-boundaries` fails otherwise.
- Native code: self-contained executable embedding Lua 5.5 (OQ-13).
- Out of scope: replacing LuaRocks.
- If your task needs a change in another package, stop and describe the needed change
  instead of making it (unless the task explicitly spans packages).

## Invariants (must hold after every change)

- never depends on a system Lua
- `install --frozen` is reproducible
- clear, actionable error messages with suggested commands

## Test strategy

- `cli-e2e` on three platforms
- template generation tests

Plus, for every change: unit tests for public behaviour, LuaLS annotations on public API
(`---@async` on anything that may suspend), README "Public API" section updated.

## Known pitfalls

- Windows paths and long path limits
- proxy and offline modes

## Standards

- LuaRocks rockspec format
- SemVer 2.0.0
