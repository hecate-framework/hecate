<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `openapi`: OpenAPI 3.1 assembly, served endpoint, export, contract diff.
- status: in-progress            <!-- in-progress | waiting-ci | waiting-owner -->
<!-- Optional, only when the owner holds this pull request for one run: - owner: session `<session id>`, why. -->
- lock_until: 2026-11-14T11:56:59Z
- last_update: 2026-11-14T10:26:59Z

## Done

- Step 1: assembly core (`openapi.build`, `encode`, components, problem details), 15 unit tests, golden file, README, CHANGELOG (e1897bb).
- CI fix: OQ-129 row moved to the open table, `gen-catalogue` refreshed.
- Step 2: contract diff `openapi.diff` (36 tests, choices in OQ-129 (11)) (ca6cb9d).

## Next steps

1. Validate output against the official OpenAPI 3.1 JSON Schema (vendor it; `conforms` helper in `packages/schema/tests/support`).
2. `securitySchemes` once the security shape is defined (OQ-113 (6)).
3. Served `/openapi.json` (development default) and reference page; needs a kernel hook.
4. `hecate contract export` hook (kernel/cli) and YAML output and the `hecate contract export` hook.
5. Lint: operation ids, descriptions, examples, undocumented responses as errors.
6. Integration tests and website reference pages.
7. CI green on three platforms, delete HANDOFF.md, tick roadmap, mark ready.

## Decisions taken (and where they are recorded)

- OQ-129 (ten conservative choices, issue #199): operationId = route name, default response when none, security copied as declared, reason phrases duplicated.

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
