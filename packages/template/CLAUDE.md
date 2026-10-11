# Agent context — `hecate.template`

You are working inside `packages/template`. Read the root `CLAUDE.md` first; this file adds
package-specific context. Specialist agent: `pkg-template`.

## Purpose

Compiled templates with contextual auto-escaping, for HTML and text responses.

## Read before changing anything

- Specification: `docs/roadmap.md`
- Decisions: none specific
- Glossary: `docs/glossary.md` · Coding standards: `docs/architecture/coding-standards.md`
- This package's `README.md` (scope, dependencies, status)

## Boundaries

- Allowed dependencies: `hecate.core`, `hecate.kernel`.
  Anything else requires an ADR; `check-boundaries` fails otherwise.
- Native code: none.
- Out of scope: client-side rendering.
- If your task needs a change in another package, stop and describe the needed change
  instead of making it (unless the task explicitly spans packages).

## Invariants (must hold after every change)

- auto-escaping on by default

## Test strategy

- XSS vectors

Plus, for every change: unit tests for public behaviour, LuaLS annotations on public API
(`---@async` on anything that may suspend), README "Public API" section updated.

## Known pitfalls

- escaping inside attributes and scripts

## Standards

- HTML Living Standard (escaping contexts)
