# Agent context — `hecate.doc`

You are working inside `packages/doc`. Read the root `CLAUDE.md` first; this file adds
package-specific context. Specialist agent: `pkg-doc`.

## Purpose

Documentation generator and static site builder with an MDN-like theme: guides in Markdown, code reference from LuaLS annotations, API reference from OpenAPI, configuration and error-code references, locales, search.

## Read before changing anything

- Specification: `docs/architecture/documentation.md`
- Decisions: `docs/adr/0012-website-generator.md`, `docs/adr/0013-english-code-multilingual-documentation.md`
- Glossary: `docs/glossary.md` · Coding standards: `docs/architecture/coding-standards.md`
- This package's `README.md` (scope, dependencies, status)

## Boundaries

- Allowed dependencies: `hecate.core`, `hecate.openapi`, `hecate.schema`, `hecate.json`.
  Anything else requires an ADR; `check-boundaries` fails otherwise.
- Native code: none.
- Out of scope: a general-purpose CMS.
- If your task needs a change in another package, stop and describe the needed change
  instead of making it (unless the task explicitly spans packages).

## Invariants (must hold after every change)

- generated pages are marked as generated and never edited by hand
- the same original, MIT-licensed theme and page template serve the framework website and user projects (ADR 0012)
- builds are deterministic (diff-friendly output)

## Test strategy

- golden files from fixture packages
- accessibility checks on the theme (contrast, keyboard navigation)

Plus, for every change: unit tests for public behaviour, LuaLS annotations on public API
(`---@async` on anything that may suspend), README "Public API" section updated.

## Known pitfalls

- LuaLS export format changes between versions: pin and test
- the Lua Web Docs theme is under the Tailwind UI licence: never copy its code or assets into `hecate.doc` (ADR 0012)

## Standards

- Diátaxis
- OpenAPI 3.1
- CommonMark
