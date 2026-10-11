# Agent context — `hecate.config`

You are working inside `packages/config`. Read the root `CLAUDE.md` first; this file adds
package-specific context. Specialist agent: `pkg-config`.

## Purpose

Layered configuration (defaults, environment files, environment variables, secrets) validated by schemas at boot.

## Read before changing anything

- Specification: `docs/architecture/overview.md`
- Decisions: none specific
- Glossary: `docs/glossary.md` · Coding standards: `docs/architecture/coding-standards.md`
- This package's `README.md` (scope, dependencies, status)

## Boundaries

- Allowed dependencies: `hecate.core`, `hecate.schema`.
  Anything else requires an ADR; `check-boundaries` fails otherwise.
- Native code: none.
- Out of scope: remote configuration services (later, by plugin).
- If your task needs a change in another package, stop and describe the needed change
  instead of making it (unless the task explicitly spans packages).

## Invariants (must hold after every change)

- configuration is immutable after boot
- unknown keys are errors

## Test strategy

- layer precedence
- error messages

Plus, for every change: unit tests for public behaviour, LuaLS annotations on public API
(`---@async` on anything that may suspend), README "Public API" section updated.

## Known pitfalls

- environment variable naming and type coercion

## Standards

- The Twelve-Factor App (configuration)
