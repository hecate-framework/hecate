# Agent context — `hecate.log`

You are working inside `packages/log`. Read the root `CLAUDE.md` first; this file adds
package-specific context. Specialist agent: `pkg-log`.

## Purpose

Structured logging with RFC 5424 severities, per-scope context and pluggable sinks.

## Read before changing anything

- Specification: `docs/architecture/logging.md` (layering: `docs/architecture/overview.md`)
- Decisions: `docs/adr/0004-academic-vocabulary.md`
- Glossary: `docs/glossary.md` · Coding standards: `docs/architecture/coding-standards.md`
- This package's `README.md` (scope, dependencies, status)

## Boundaries

- Allowed dependencies: `hecate.core`, `hecate.reactor`, `hecate.json`.
  Anything else requires an ADR; `check-boundaries` fails otherwise.
- Native code: none.
- Out of scope: metrics and tracing (later, OpenTelemetry-compatible package).
- If your task needs a change in another package, stop and describe the needed change
  instead of making it (unless the task explicitly spans packages).

## Invariants (must hold after every change)

- logging never suspends the caller on the hot path
- secrets marked as such are never rendered

## Test strategy

- context propagation across fork/join
- sink back-pressure

Plus, for every change: unit tests for public behaviour, LuaLS annotations on public API
(`---@async` on anything that may suspend), README "Public API" section updated.

## Known pitfalls

- string formatting cost when the severity is disabled

## Standards

- RFC 5424 severities
