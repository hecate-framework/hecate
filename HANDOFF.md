<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: **Phase 2 gate**: verification of the phase, as described in "Phase gates" (`docs/roadmap.md`).
- status: in-progress
- lock_until: 2026-11-13T17:00:00Z
- last_update: 2026-11-13T15:30:00Z

## Done

- Claimed the gate; pull request 183 (title now `docs(reviews): ...`, the `title` check needs a type).
- Step 1 "It works" (at `main` eb9d9b7), report section 2: every check, `build-native json|doc|http|net`,
  `typecheck`, `test` (all packages, `tools`, `examples/hello`), `leaks`, `bench plaintext` and `kernel-json` ok;
  CI of eb9d9b7 green on the three platforms. G1 (gen checks not in CI) and G2 (README statuses) fixed.
- G3 fixed: `bench <scenario> --runs` names `--rounds` (41c4795).
- G4, roadmap triage item: `Application:serve` without the `http` native module raises `ModuleError`
  `http_unavailable` naming `build-native http`.
- Issue 184 (stale idle notice) closed.
- Completeness audit received (agent report, to paste into section 1); its gaps 2 (OQ-86 fallback of `schema` on the
  default logger) and 3 (`json_equal` read the depth limit once) fixed, test first.
- Coherence audit written: `docs/reviews/phase-2-coherence-findings.md` (C1 to C32).
- Safe content canary test committed as work in progress
  (`packages/kernel/tests/integration/safe_content_canary_test.lua`, final).
- Report sections 1, 3, 4 and 5 written; findings P1 to P8, S1 to S7 in section 6 with their dispositions.
- G5 fixed: coverage marker around the pool-thread body of `offload`; `reactor` 90.8 % (nightly failed at 89.8 %).
- Coherence pass: 28 findings fixed (C24 left for the http agent); OQ-120 to OQ-122 added (issues 185 to 187);
  OQ-69 known limitation (P4); OQ-24 moved to Resolved (issue 64 closed). Owner issue: 188 (`needs-decision`).
- P1, S1, S2, S7 and C24 fixed (`Request.content`, production checklist, tests). Every row of section 6 of the
  report now has a final disposition; the coherence findings too (C10, C11, C25, C32 with the owner).

## Next steps

1. Reviewer wave, findings in `docs/reviews/phase-2-review-package.md` (container, config, router, reactor, kernel
   recorded; `http` reviewer still running). Fix agents running in parallel (no commits of their own): container
   (CT-1, CT-3 to CT-6, CT-8 to CT-12, plus `Container:has` for K-3), config (CF-1 to CF-11, also `log` secret),
   router (R-1 to R-7), reactor (RE-1 to RE-3, RE-6 to RE-9, RE-4 docs), kernel (K-1, K-2, K-4 to K-6, K-8 to K-13,
   K-15, CT-2; K-3 once `Container:has` exists). Then: `http` fixes (after the kernel agent, which may touch `http`
   for CT-2); review each agent's diff, run the full checks, add CHANGELOG lines, set every row's disposition,
   commit and push. Deferred already: CT-7 OQ-123, CF-12/13 OQ-124, RE-5 OQ-125, K-7 OQ-126 (issues 189 to 192);
   R-2 indexing, RE-4 measurement, K-14 in roadmap Continuous. If a run finds the agents gone: redo from the
   `Open` rows of the review file (check `git status` for partial work first).
2. Wait for the owner on issue 188 (section 5 questions); then record each answer in `docs/open-questions.md`.
3. Finish: tick the gate only when the report shows no open gap and every question has an owner decision or deferral.

## Decisions taken (and where they are recorded)

- Phase 2 packages get README status `alpha` after the gate, as the Phase 1 packages did; `hecate` stays
  `in progress` (standard edition in Phase 3). Report G2.

## Doubts and questions for the owner

## Commands to re-run

```sh
eval "$(luarocks path)"         # luv under /opt/lua-5.5 is found only this way
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
