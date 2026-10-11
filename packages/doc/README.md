# `hecate-doc`

> Documentation generator and static site builder with an MDN-like theme: guides in Markdown, code reference from LuaLS annotations, API reference from OpenAPI, configuration and error-code references, locales, search.

| | |
|---|---|
| Module | `hecate.doc` |
| Rock | `hecate-doc` |
| Layer | Tooling |
| Roadmap phase | 3 |
| Status | specified — no code yet |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`openapi`](../openapi), [`schema`](../schema), [`json`](../json) |
| Used by | `cli` |
| Native code | none |
| Specification | [documentation.md](../../docs/architecture/documentation.md) |
| Decisions | [ADR 0012](../../docs/adr/0012-website-generator.md), [ADR 0013](../../docs/adr/0013-english-code-multilingual-documentation.md) |
| Agent | [`pkg-doc`](../../.claude/agents/pkg-doc.md) |
| Repository | read-only mirror `hecate-framework/hecate-doc`, generated from this directory (ADR 0017) |

## Responsibilities

- consume `lua-language-server --doc` JSON export and the route/schema metadata
- render Markdown guides (CommonMark + front matter) and generated reference pages with one MDN-like theme (page template in documentation.md)
- locales with fallback and translation status (`source_revision`)
- static search index
- versioned documentation per minor release
- runnable examples for pure-Lua packages if Lua 5.5 builds to WebAssembly (OQ-11)
- `hecate doc build|serve` for user projects with the same theme, with a base URL option for GitHub Pages project sites
- `llms.txt` and `llms-full.txt` generation
- stable anchors per symbol

## Non-goals

- a general-purpose CMS

## Standards and references

- Diátaxis
- OpenAPI 3.1
- CommonMark

## Public API

*To be filled during implementation: list every exported class and function with a one-line
description, linking to the generated reference.*

## Layout (once implemented)

```text
src/hecate/doc/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
```
