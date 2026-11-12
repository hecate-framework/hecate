<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Benchmarks: plaintext and JSON scenarios. (Phase 2, with the deferred performance findings RE2, J4, LO4, the router findings and the schema findings P5, P6)
- status: in-progress
- lock_until: 2026-11-12T11:33:54Z
- last_update: 2026-11-12T10:03:54Z

## Done

- Step 1 (4540674): scenarios `plaintext` (`http.Server` alone) and `kernel-json` (`kernel.Application`, one route,
  represent and encode), shared open-loop HTTP load generator `benchmarks/lib/http_load.lua` (`--pipeline=N`,
  `--path`), `benchmarks/lib/setup.lua`, smoke tests in `tools/tests/benchmark_scenario_test.lua`.
- Step 2 (284170f, French page in the next commit): `benchmarks.yml` is a matrix over `tcp-echo`, `plaintext` and
  `kernel-json` (HTTP ones build `json` and `http` natives, 100 connections at 2 000 requests/s); README section and
  how-to page (English and French) updated. `bench kernel-json --compare=origin/main` checked locally.
- Step 3 (de7ae45): findings RE2, J4, LO4, router, P5, P6 measured and kept, report `docs/reviews/phase-2-benchmarks.md`,
  review rows updated; two reactor experiments (RE2 without `table.pack`, indexed timer heap) gave no significant change
  and were reverted; `schema/validate` micro-benchmark fixed; `bench` summary parsing deferred to roadmap "Continuous";
  P5 pointer added to the Phase 4 database benchmarks item; CHANGELOG entry.

## Next steps

1. Reviewer pass (performance-engineer, test-engineer) on the diff; fix what they find.
2. CI green on the three platforms, and `benchmarks.yml` (three matrix jobs; the PR has the `performance` label).
3. Finish: tick the roadmap item, delete `HANDOFF.md`, mark the PR ready, ask the owner for review.

## Decisions taken (and where they are recorded)

- The JSON scenario is named `kernel-json`, not `json` as in the README table: `bench <name>` resolves a scenario
  before a package, so a scenario `json` would hide the `json` codec micro-benchmarks (`bench json`). To record in
  `benchmarks/README.md` (step 2) and the PR description.
- The load generator is the Lua one of the repository (no `wrk2`/`oha`, no new dependency), as for `tcp-echo`.

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
