# 0018 — Error signalling: raise error objects, return nil for expected absence

- **Status:** Accepted
- **Date:** 2026-10-11
- **Deciders:** project owner
- **Packages:** all
- **Related:** [object-model.md](../architecture/object-model.md#errors), [coding-standards.md](../architecture/coding-standards.md#errors), OQ-9 (resolved), ADR 0003

## Context

Lua offers two idioms: raising errors (`error`, caught with `pcall`) and returning
`nil, message`. Hecate needs one convention across every package. Transparent
concurrency (ADR 0003) makes code read sequentially, so failures should interrupt the
flow without manual propagation at every level.

## Options considered

1. **Raise error objects; return `nil` for expected absence.**
2. **`nil, err` everywhere.** Classic Lua idiom; verbose propagation; ignored errors pass
   silently.
3. **Raise everywhere, absence included.** Strict; forces `pcall` for normal cases.

## Decision

Option 1.

- Failures (I/O failure, protocol error, invalid input, misconfiguration, programmer
  error, cancellation, deadline) **raise** an instance of the `hecate.core.Error`
  hierarchy, with a stable `code`, a message, optional `cause` and `context`.
- **Expected absence returns `nil`** (`repository:find(id)`, `headers:get(name)`,
  `cache:get(key)`). The function's documentation states when `nil` is returned.
- Public APIs never return `nil, message` pairs.
- A boolean-returning variant may exist when failure is a normal outcome and its name
  says so (`try_acquire`, `try_parse`), returning `false` or `nil` without raising.
- The kernel maps uncaught errors to RFC 9457 problem details through an explicit
  mapping (validation → 422, not found → 404, ...; anything unmapped → 500 without
  internal details).
- Errors raised inside forked computations propagate to `join`/`select` and to the
  enclosing scope (ADR 0003).

## Consequences

- Short, sequential business code; one place (the kernel or a filter) handles errors
  for HTTP.
- `pcall` is reserved for code that genuinely recovers.
- Every error class and code is documented on the website (`gen-error-codes`).

## Verification

`check-annotations` requires `---@return T?` (nullable) on functions that return `nil`
for absence; lint rule forbidding `return nil, "..."` patterns in `packages/**/src`.
