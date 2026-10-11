# `hecate-security`

> Authentication (bearer tokens, JWT, sessions), authorisation policies, password hashing.

| | |
|---|---|
| Module | `hecate.security` |
| Rock | `hecate-security` |
| Layer | Framework |
| Roadmap phase | 5 |
| Status | planned — no code yet |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`kernel`](../kernel), [`schema`](../schema), [`json`](../json) |
| Used by | — |
| Native code | crypto via TLS binding |
| Specification | [roadmap.md](../../docs/roadmap.md) |
| Decisions | — |
| Agent | [`pkg-security`](../../.claude/agents/pkg-security.md) |
| Repository | read-only mirror `hecate-framework/hecate-security`, generated from this directory (ADR 0017) |

## Responsibilities

- authenticators as filters
- policies (attribute-based)
- password hashing (Argon2id)
- OpenAPI security schemes emission

## Non-goals

- identity provider

## Standards and references

- RFC 7519 (JWT)
- RFC 6750 (bearer tokens)
- RFC 9106 (Argon2)
- OWASP ASVS

## Public API

*To be filled during implementation: list every exported class and function with a one-line
description, linking to the generated reference.*

## Layout (once implemented)

```text
src/hecate/security/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
csrc/        native sources
```
