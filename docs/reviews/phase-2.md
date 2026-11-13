# Phase 2 gate report

Date: 2026-11-13. Pass at the head of `claude/relay-phase-2-gate` (pull request 183), which holds `main` eb9d9b7
(merge of pull request 182) plus the fixes listed below, on Linux (Ubuntu 24.04 x86_64, Lua 5.5, GCC 13, cargo).
Windows is not a benchmark target.

Scope: completeness (section 1), it works (section 2), coherence (section 3), safe content (section 4, OQ-111),
open questions (section 5), and the findings with their disposition (section 6).

## 1. Completeness

To be written (next step of the gate).

## 2. It works

Every command below ran from this checkout, with `eval "$(luarocks path)"` (the cloud image installs `luv` under
`/opt/lua-5.5`, found only this way).

| Command | Result |
|---|---|
| `check-adr-index`, `check-annotations`, `check-boundaries`, `check-changelog --base origin/main`, `check-docs-examples`, `check-examples`, `check-glossary`, `check-licenses`, `check-links`, `check-lua-constructs`, `check-package-structure`, `check-rockspecs`, `check-versions`, `lint`, `format-check` | ok |
| `gen-catalogue --check`, `gen-llms-txt --check`, `gen-dependency-graph --check` | ok after regeneration in this branch (finding G1) |
| `build-native json`, `build-native doc`, `build-native http`, `build-native net` | ok |
| `setup-luals`, then `typecheck` | ok, zero diagnostics |
| `test` (the 30 packages; 192 test files) | ok, about 60 s |
| `test tools` | ok |
| `test examples/hello` (in process, and two workers with `round_robin`, including a request in flight during the graceful shutdown) | ok |
| `check-examples` and the shared runner `tools/harness/examples.lua` (the two example rules) | ok: every example of `packages/*/examples/`, `examples/` and the website passes both rules |
| `bench plaintext --rounds=1 --duration=3 --warmup=1` | ok: 1000 requests/s offered and served, 0 errors, 0 bad responses, p50 1.19 ms, p99 5.9 ms |
| `bench kernel-json --rounds=1 --duration=3 --warmup=1` | ok: 1000 requests/s, 0 errors, 0 bad responses, p50 1.15 ms, p99 5.5 ms |
| `leaks` (`reactor`, `net`) | ok |
| CI of `main` eb9d9b7 | `ci` green on `ubuntu-latest`, `macos-latest` and `windows-latest` (run 43399777184); `docs`, `website` and `benchmarks` green |

**Exit criteria of the phase.** `examples/hello` runs on the three platforms with N workers (its tests run in the
`Test` step of the three `ci` jobs whenever the kernel is affected, and ran green at eb9d9b7); invalid input yields
RFC 9457 problem details (`422` with `source`, tested by `examples/hello/tests`); the graceful shutdown drains
requests in flight (tested with two workers).

## 3. Coherence

To be written.

## 4. Safe content (OQ-111)

To be written.

## 5. Open questions

To be written.

## 6. Findings and disposition

| Id | Finding | Disposition |
|---|---|---|
| G1 | `packages/README.md` and `llms.txt` were stale (the `container`, `kernel` and `hecate` statuses, the `reactor` summary) and CI never ran `gen-catalogue --check`, `gen-llms-txt --check` or `gen-dependency-graph --check`. | Fixed: regenerated, and the three checks added to the `docs-checks` job and to the static checks of `ci.yml`. |
| G2 | The README status of `kernel` was still `in progress` although its item is ticked; `http`, `router`, `schema`, `container` and `config` gave `implemented`, which is not a status of `packages/README.md` (`specified`, `planned`, `in progress`, `alpha`, `stable`); `hecate` said `implemented` although the standard edition is a Phase 3 item. | Fixed: `alpha` for the six Phase 2 packages (as the Phase 1 packages after their gate), `in progress` for `hecate`. |
| G3 | `bench <scenario> --runs=N` (the option `bench --list` advertises) fails with `unknown argument '--runs=1'`, printed twice, without naming `--rounds`, the option of the scenarios. | To triage (minor, tooling). |
