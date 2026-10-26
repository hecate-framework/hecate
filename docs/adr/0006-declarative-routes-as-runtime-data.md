# 0006 — Routes declared as runtime data, not comment annotations

- **Status:** Accepted
- **Date:** 2026-10-11
- **Deciders:** project owner
- **Packages:** kernel, router, schema, openapi, doc, test
- **Related:** [http-and-routing.md](../architecture/http-and-routing.md), [schemas-and-contracts.md](../architecture/schemas-and-contracts.md)

## Context

The owner wanted routes declared next to their actions rather than in a central
configuration file, ideally through annotations. Lua comments do not exist at run time;
annotation-based routing requires parsing source files and inventing tags that LuaLS
does not understand (`---@route`, status codes on `---@return`), losing the IDE support
that motivated annotations. LuaLS also has no notion of path/query/field/content
parameters.

## Options considered

1. **Comment annotations parsed at build or boot.** Familiar look; needs a parser for
   LuaLS type grammar; no runtime introspection; custom tags degrade IDE support.
2. **Declarative Lua data next to the action** (`controller:route { ... }` or
   `routes:get "/path" { ... }`). Introspectable at run time; one source of truth for
   validation, OpenAPI, documentation and contract tests.

## Decision

Option 2. Routes, parameters and responses are Lua values built with `hecate.schema`.
Two styles (controller classes and lightweight route modules) produce the same route
table. LuaLS annotations remain mandatory for typing and code documentation; the CLI can
generate LuaLS `---@meta` definitions from schemas so that request objects are typed in
the editor.

## Consequences

- No central route file, no source parsing, no drift between documentation and
  behaviour.
- Boot-time validation of the entire route table.

## Verification

`openapi` tests compare generated documents with golden files; `kernel` tests assert
that both declaration styles produce identical route tables.
