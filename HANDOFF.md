<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Benchmarks: plaintext and JSON scenarios. (Phase 2, with the deferred performance findings RE2, J4, LO4, the router findings and the schema findings P5, P6)
- status: in-progress
- lock_until: 2026-11-12T11:20:05Z
- last_update: 2026-11-12T09:50:05Z

## Done

- Step 1 (4540674): scenarios `plaintext` (`http.Server` alone) and `kernel-json` (`kernel.Application`, one route,
  represent and encode), shared open-loop HTTP load generator `benchmarks/lib/http_load.lua` (`--pipeline=N`,
  `--path`), `benchmarks/lib/setup.lua`, smoke tests in `tools/tests/benchmark_scenario_test.lua`.
- Step 2 (284170f, French page in the next commit): `benchmarks.yml` is a matrix over `tcp-echo`, `plaintext` and
  `kernel-json` (HTTP ones build `json` and `http` natives, 100 connections at 2 000 requests/s); README section and
  how-to page (English and French) updated. `bench kernel-json --compare=origin/main` checked locally.

## Next steps

1. Judge the deferred findings with measurements (RE2, J4, LO4; router; schema P5, P6): keep or fix each, note the
   result in `docs/reviews/phase-1-review-package.md`, `docs/reviews/schema-review-package.md` and the router review.
   Local indication (cloud VM, not quotable): one server process saturates at about 7 000 to 8 500 requests/s for
   both `plaintext` and `kernel-json`, pipelining does not raise it, so the HTTP stack dominates; profile `plaintext`.
2. CHANGELOG, roadmap tick, CI green on three platforms (label `performance` is on the PR, so `benchmarks.yml` runs).

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
