<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: **Phase 2 gate**: verification of the phase, as described in "Phase gates" (`docs/roadmap.md`).
- status: in-progress
- lock_until: 2026-11-13T23:00:00Z
- last_update: 2026-11-13T21:20:00Z

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
- Reviewer wave done (`docs/reviews/phase-2-review-package.md`): every finding fixed test first or deferred, H-4 and L-1 included; deferred ones in OQ-123 to OQ-127 (issues 189 to 193) and roadmap "Continuous".

## Next steps

1. Owner answers still awaited in the session: OQ-77 (name: `StateError` or `IllegalStateError`) and OQ-82
   (stalled content: `ContentError` reason `timeout` on both sides; the client error for a too-large response
   without a status; the `url.decode_segment` point obsolete). Then record them and close issues 91 and 90.
2. Every other question is answered (decisions of 2026-11-13 recorded in `docs/open-questions.md`, issues closed;
   OQ-13 and OQ-17 stay open as Phase 3 spikes, relabelled `due:phase-3`).
3. Check CI green on the three platforms, then finish: delete this file, tick the gate in `docs/roadmap.md`, mark
   the pull request ready for review, ask the owner for review in a comment. Never merge.

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
