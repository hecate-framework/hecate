<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: **Phase 2 gate**: verification of the phase, as described in "Phase gates" (`docs/roadmap.md`).
- status: in-progress
- lock_until: 2026-11-13T12:45:00Z
- last_update: 2026-11-13T11:15:00Z

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
  (`packages/kernel/tests/integration/safe_content_canary_test.lua`); the audit agent is still finishing it.

## Next steps

1. Report section 1 from the completeness audit: table per item; remaining gaps: (1) narrow `Request.content`
   (`http/request.lua:20`, `:30`: drop `function`, document nil from the server and the validated value);
   (4) OQ-69 per-address TLS handshake cap: record as known limitation or re-home; (5) `automation.md:76` reference
   set (= C13); (6) container scope micro-benchmark: defer to roadmap "Continuous"; (7) kernel how-to and examples:
   name them in the Phase 3 website item; (8) `schema-review-package.md:39-40` s5, s6 statuses.
2. Coherence findings: fix the 28 text edits (C1 to C9, C12 to C24, C26 to C31), give each a disposition in the
   findings file; C10, C11, C25, C32 need the owner: open-questions entries (with mirror issues).
3. Safe content (section 4) from the audit agent's report; fix or defer each finding.
4. `coverage`: `reactor` 89.8 % (< 90 %) locally; compare with the nightly of eb9d9b7 (run 43403344037).
5. Reviewer wave (`/review-package` on the Phase 2 packages), triage each minor.
6. Section 5: the open `due:phase-2` issues 56 OQ-46, 60 OQ-17, 61 OQ-13, 64 OQ-24 (owner decision recorded: move
   to Resolved), 72 OQ-38, 77 OQ-64, 81 OQ-75, 83 OQ-69, 87 OQ-73, 90 OQ-82, 91 OQ-77, plus C10, C11, C25, C32;
   recommendation each, one `needs-decision` issue.
7. Finish: tick the gate only when the report shows no open gap and every question has an owner decision or deferral.

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
