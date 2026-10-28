# 0004 — Academic vocabulary for names

- **Status:** Accepted
- **Date:** 2026-10-11
- **Deciders:** project owner
- **Packages:** all
- **Related:** [glossary.md](../glossary.md)

## Context

Lua itself names things after the literature (coroutine, closure, upvalue, metatable).
The owner wants Hecate to do the same rather than paraphrase vocabulary popularised by
other languages.

## Decision

- [glossary.md](../glossary.md) is normative for public APIs, documentation and code.
- Standards keep their own terms (RFC 9110, RFC 9457, JSON Schema, OpenAPI, SQL).
- When a theoretical term collides with a practical one (σ *selection* versus SQL
  `SELECT`), the theoretical term is used and the correspondence is documented
  prominently.
- New terms are added to the glossary in the same pull request that introduces them,
  with a reference.

## Consequences

- Consistent, predictable names; steeper first contact for users of other frameworks,
  mitigated by "Instead of" columns and correspondence tables in the documentation.

## Verification

`check-glossary` task: a deny-list of discouraged identifiers (`promise`, `spawn`,
`middleware`, ...; the list is `M.denied` in `tools/lib/glossary.lua`) scanned in `packages/**/src`; the `terminology-reviewer`
agent reviews pull requests.
