# Agent context — `hecate.security`

You are working inside `packages/security`. Read the root `CLAUDE.md` first; this file adds
package-specific context. Specialist agent: `pkg-security`.

## Purpose

Authentication (bearer tokens, JWT, sessions), authorisation policies, password hashing.

## Read before changing anything

- Specification: `docs/roadmap.md`
- Decisions: none specific
- Glossary: `docs/glossary.md` · Coding standards: `docs/architecture/coding-standards.md`
- This package's `README.md` (scope, dependencies, status)

## Boundaries

- Allowed dependencies: `hecate.core`, `hecate.kernel`, `hecate.schema`, `hecate.json`.
  Anything else requires an ADR; `check-boundaries` fails otherwise.
- Native code: crypto via TLS binding.
- Out of scope: identity provider.
- If your task needs a change in another package, stop and describe the needed change
  instead of making it (unless the task explicitly spans packages).

## Invariants (must hold after every change)

- constant-time comparisons
- secure defaults

## Test strategy

- security test vectors

Plus, for every change: unit tests for public behaviour, LuaLS annotations on public API
(`---@async` on anything that may suspend), README "Public API" section updated.

## Known pitfalls

- algorithm confusion in JWT

## Standards

- RFC 7519 (JWT)
- RFC 6750 (bearer tokens)
- RFC 9106 (Argon2)
- OWASP ASVS
