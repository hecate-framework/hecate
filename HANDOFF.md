<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: **Phase 1 gate**: verification of the phase, as described in Phase gates. Open questions to put to the owner before Phase 2: OQ-50, OQ-47, OQ-23, OQ-24, OQ-26 (1) and OQ-22.
- status: in-progress
- lock_until: 2026-10-27T23:14:27Z
- last_update: 2026-10-27T21:44:27Z

## Done

- Claimed the gate (PR #40 merged, benchmarks item ticked).
- Ran all check tasks, build-native json/doc, full test, bench tcp-echo: all ok. Wrote docs/reviews/phase-1.md (coherence pending).
- Cloud tip: run `eval "$(luarocks path)"` before `test`, else luv is not found.

## Next steps

Step done 2026-10-27 (run 4): Part B finished: all small findings fixed (B18 was already in order; B32: stamps bumped for the five pages compared in scope, the 7 other French pages not compared: left for the A44/B32 deferral). Next: Part C small findings (docs/reviews/_phase-1-part-C.md, skip D items), then merge parts into phase-1-coherence-findings.md, phase-1.md section 3, /review-package, tick the gate. Re-run: `eval "$(luarocks path)"`; `lua tools/run.lua build-native json` and `doc` before tests.

Step done 2026-10-27 (run 3): Part B partly fixed: B08-B11, B14 (README, CHANGELOG, how-to), B12, B17, B21, B26 (workflow loop; the reference index already had log), B27, B28, B29 (done in docs and sources). Remaining part B: B01-B07, B13, B15, B16, B18-B20, B22-B25, B30-B32. Then Part C, merge parts, phase-1.md section 3, /review-package. Note: run `lua tools/run.lua build-native json` before testing log, else json-dependent tests fail.

Step done 2026-10-27 (run 2): Part A small findings fixed (all S except A02, A44 skipped; A29, A33, A40, A41, A42 are owner items). A02 (~30 core error messages: convert to qualified prefix or state exception in coding-standards.md) and A44 (French source_revision bump after checking each page) left. Next: same for Part B, then Part C (agent: general-purpose, give it the part file, skip D items, no commit), then merge parts into phase-1-coherence-findings.md, update phase-1.md section 3, run /review-package. Re-run: `eval "$(luarocks path)"` before `lua tools/run.lua test <pkg>`.

Owner answered OQ-50/47/23/24/26/22 on 2026-10-27 (recorded in docs/open-questions.md). Open: OQ-50 presence set vs json.null, OQ-26 (4) virtual clock. Roadmap items for those answers added before the gate (reactor follow-up, net follow-up). Next: the coherence fixes (small findings of parts A, B, C); the seven D findings and the ambient-context glossary entry still await the owner.

Coherence audit done in three raw parts (docs/reviews/_phase-1-part-{A,B,C}.md: 45+32+27 findings). Next: owner answers on the D items and the six OQs; then fix the small findings in this PR, merge the parts into phase-1-coherence-findings.md, update phase-1.md section 3, run /review-package. DONE earlier: sections 1, 2, 4 of docs/reviews/phase-1.md. Remaining: section 3 coherence audit (file by file, as phase-0-coherence-findings.md) and /review-package on core, reactor, net, json, log, doc; then owner decisions on OQ-50/47/23/24/26/22 (issue opened); then tick the gate and delete this file.

- Completeness: read every ticked Phase 1 item against its spec and the definition of done.
- It works: run the check catalogue, native builds, tests, examples, benchmarks; read CI of latest main.
- Coherence: docs, ADRs, README, website en/fr, llms.txt.
- Write docs/reviews/phase-1.md; update docs/open-questions.md; open/update needs-decision issue.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

## Commands to re-run

```sh
```
