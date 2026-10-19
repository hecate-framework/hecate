<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `json`: codec (after OQ-5).
- status: in-progress
- lock_until: 2026-10-19T11:18:42Z
- last_update: 2026-10-19T09:48:42Z

## Done

- Claimed (PR #25). Website item is in PR #24 (owner's), skipped.
- Step 1 (5ac3128): Lua side. Public API, markers, errors, backend seam (`hecate.json.internal.backend`), pure-Lua reference backend (fallback + test oracle), unit/property tests, README, CHANGELOG, OQ-48. `test json`, lint and the check-* gates pass; `typecheck` not run (no lua-language-server here).

## Next steps

1. Native yyjson decoder binding following the `hecate.json.native` contract in `internal/backend.lua`; run shared tests against both backends.
2. serde_json encoder via mlua (ADR 0021) in `packages/json/native`, matching float formatting and markers.
3. Streaming/incremental decoder.
4. JSONTestSuite corpus in tests/fixtures, run on both backends; fuzzing.
5. Benchmarks, website reference page, examples for the doc generator.

## Decisions taken (and where they are recorded)

- Work is on the session branch `claude/sweet-feynman-1zqg2u`, not `claude/relay-json`.
- Defaults (max_depth 1000/ceiling 10000, max_size 16 MiB, canonical = byte order) in OQ-48.

## Doubts and questions for the owner

- OQ-48: empty unmarked table encodes as {}; `markers.lua` aliases setmetatable to get past check-boundaries (owner: allow json in the check, or a core tagging primitive); error root JsonError; is_array/is_object exported.

## Commands to re-run

```sh
lua tools/run.lua test json
lua tools/run.lua lint
lua tools/run.lua check-boundaries
```
