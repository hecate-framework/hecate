<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: **Phase 2 gate**: verification of the phase, as described in "Phase gates" (`docs/roadmap.md`).
- status: in-progress
- lock_until: 2026-11-13T12:30:00Z
- last_update: 2026-11-13T11:00:00Z

## Unblocked

#182 (the examples item) was merged on 2026-11-13 and `main` is merged into this branch: every Phase 2 item
but the gate is ticked. Continue from "Next steps" (redo step 1 at the new `main`; the gate now also checks the two
example rules, `check-examples` and the examples tests).

## Done

- Claimed the gate (branch `claude/relay-phase-2-gate`, draft pull request). Issue #180 closed (#179 merged).
- Partial step 1 (at `main` 0e1616c): every `check-*`, `lint`, `format-check`, `gen-dependency-graph --check` ok;
  `build-native json|doc|http|net` ok. Findings: `gen-catalogue --check` and `gen-llms-txt --check` failed (stale,
  regenerated in this branch; CI does not run them: check why); `packages/kernel/README.md` status still `in progress`
  although the item is ticked.
- Step 1 "It works" (at `main` eb9d9b7): every check, `build-native json|doc|http|net`, `typecheck`, `test` (all
  packages, `tools`, `examples/hello`), `leaks`, `bench plaintext` and `kernel-json` ok; CI of eb9d9b7 green on the
  three platforms. Recorded in `docs/reviews/phase-2.md` section 2, with findings G1 (gen checks not in CI: fixed),
  G2 (README statuses: fixed), G3 (`bench <scenario> --runs` message: to triage). `coverage`: every package at or above its threshold but `reactor` 89.8 % (< 90 %) locally; compare with the
  nightly of eb9d9b7 (run 43403344037) before deciding (report row G5, to add).
- Step 3, roadmap triage item: `Application:serve` without the `http` native module raises `ModuleError`
  `http_unavailable` naming `build-native http` (test first; report row G4).
- G3 fixed (`bench <scenario> --runs` names `--rounds`), 41c4795. Issue #184 (stale idle notice) closed.
- Steps 2, 4 and 5 delegated to three agents (completeness, coherence into
  `docs/reviews/phase-2-coherence-findings.md`, safe content with the canary test
  `packages/kernel/tests/integration/safe_content_canary_test.lua`); interrupted once by a usage limit, resumed.
  If a run finds them gone, redo those steps.
- Step 7 prepared: the open `due:phase-2` issues are #56 OQ-46, #60 OQ-17, #61 OQ-13, #64 OQ-24 (owner decision
  recorded: move to Resolved), #72 OQ-38, #77 OQ-64, #81 OQ-75, #83 OQ-69, #87 OQ-73, #90 OQ-82, #91 OQ-77; each
  needs a line in section 5 with a recommendation and one `needs-decision` issue.

## Next steps

2. Completeness: one row per ticked Phase 2 item (section 1 of the report), with code, tests, README status,
   website reference, CHANGELOG, benchmarks; grep `TODO|FIXME|not implemented` in the Phase 2 packages.
4. Coherence audit (code, ADRs, specs, READMEs, glossary, roadmap, open questions, website, `automation.md`,
   `llms.txt`, `README.md`, `CLAUDE.md`), findings in `docs/reviews/phase-2-coherence-findings.md`; fix or defer each.
5. Safe content audit (OQ-111): grep messages and `logger:*` calls of `http`, `router`, `schema`, `container`,
   `config`, `kernel`; canary test; check `website/en/how-to/before-going-to-production.md` against the phase.
6. Reviewer wave (`/review-package` on the Phase 2 packages), triage each minor (fix or defer with a pointer).
7. Open questions OQ-46, OQ-13, OQ-17, OQ-38, OQ-64 (and any made stale): context and recommendation in the report,
   one `needs-decision` issue. Never decide them.
8. Finish: tick the gate only when the report shows no open gap and every question has an owner decision or deferral.

## Decisions taken (and where they are recorded)

- Phase 2 packages get README status `alpha` after the gate, as the Phase 1 packages did (`implemented` is not a
  status); `hecate` stays `in progress` (standard edition in Phase 3). Report G2.

## Doubts and questions for the owner

## Commands to re-run

```sh
eval "$(luarocks path)"         # luv under /opt/lua-5.5 is found only this way
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
