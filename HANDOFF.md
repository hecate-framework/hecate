<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `openapi`: OpenAPI 3.1 assembly, served endpoint, export, contract diff.
- status: in-progress            <!-- in-progress | waiting-ci | waiting-owner -->
<!-- Optional, only when the owner holds this pull request for one run: - owner: session `<session id>`, why. -->
- lock_until: 2026-11-14T12:54:18Z
- last_update: 2026-11-14T11:24:18Z

## Done

- Step 1: assembly core (`openapi.build`, `encode`, components, problem details), 15 unit tests, golden file, README, CHANGELOG (e1897bb).
- CI fix: OQ-129 row moved to the open table, `gen-catalogue` refreshed.
- Step 2: contract diff `openapi.diff` (36 tests, choices in OQ-129 (11)) (ca6cb9d).
- Owner answers on OQ-129 recorded (OQ-129 row, roadmap).
- Kernel: route `name` mandatory, no default name (8458973). Kernel integration tests that need native modules could not run in the sandbox: CI decides.
- Core: `hecate.core.status` table and `core.Problem` interface (data fields added to `core.interface`: owner to confirm, not in ADR 0007).

## Next steps

1. `http`: make `http/status.lua` delegate to `core.status` (alias `http.Status`).
2. `kernel`: problem classes made by `declare`/`define` declare `core.Problem` (not the bare base class); use `core.status.reason`; route flag `content_optional` (the input step accepts an absent body).
3. `openapi`: drop `internal/status.lua` (keep the class-label fallback), recognise problems with `core.implements(value, core.Problem)`; ordered `tags` list with descriptions and `externalDocs` in the settings; `operationId` is the name; document `{rest...}` as `{rest}`.
4. Validate output against the official OpenAPI 3.1 JSON Schema (vendor it; `conforms` helper in `packages/schema/tests/support`).
5. Served `/openapi.json` (development default) and reference page; needs a kernel hook.
6. YAML output and the `hecate contract export` hook (kernel/cli).
7. Lint: names, descriptions, examples, undocumented responses as errors, unused listed tags.
8. Integration tests and website reference pages (`{rest...}` documented).
9. CI green on three platforms, delete HANDOFF.md, tick roadmap, mark ready.

## Decisions taken (and where they are recorded)

- OQ-129 (ten conservative choices, issue #199): operationId = route name, default response when none, security copied as declared, reason phrases duplicated.

## Doubts and questions for the owner

- Data fields on `core.interface` (extension, ADR 0007 untouched): confirm or use accessor methods.
- Stray files `/before.txt` and `/after.txt` at the filesystem root of the sandbox (harmless; not in the repository).
- Never leave a git worktree under `.claude/worktrees/` while running `typecheck`: it duplicates every file (3571 warnings).

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
