<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: **Phase 2 gate**: verification of the phase, as described in "Phase gates" (`docs/roadmap.md`).
- status: in-progress
- lock_until: 2026-11-13T11:15:00Z
- last_update: 2026-11-13T09:45:00Z

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

## Next steps

1. "It works": from this checkout, run the full check catalogue (`lua tools/run.lua --list`), the native builds
   (`build-native json|doc|http|net`), `test` for every package and `tools`, the `examples/hello` tests, the
   benchmark scenarios `plaintext` and `kernel-json`; read the CI of the latest `main` (0e1616c) on the three
   platforms. Record each command and result in `docs/reviews/phase-2.md`, section 2.
2. Completeness: one row per ticked Phase 2 item (section 1 of the report), with code, tests, README status,
   website reference, CHANGELOG, benchmarks; grep `TODO|FIXME|not implemented` in the Phase 2 packages.
3. Triage item named by the roadmap: `Application:serve` without the `http` native module must raise an error naming
   `lua tools/run.lua build-native http` (test first, `pkg-kernel`).
4. Coherence audit (code, ADRs, specs, READMEs, glossary, roadmap, open questions, website, `automation.md`,
   `llms.txt`, `README.md`, `CLAUDE.md`), findings in `docs/reviews/phase-2-coherence-findings.md`; fix or defer each.
5. Safe content audit (OQ-111): grep messages and `logger:*` calls of `http`, `router`, `schema`, `container`,
   `config`, `kernel`; canary test; check `website/en/how-to/before-going-to-production.md` against the phase.
6. Reviewer wave (`/review-package` on the Phase 2 packages), triage each minor (fix or defer with a pointer).
7. Open questions OQ-46, OQ-13, OQ-17, OQ-38, OQ-64 (and any made stale): context and recommendation in the report,
   one `needs-decision` issue. Never decide them.
8. Finish: tick the gate only when the report shows no open gap and every question has an owner decision or deferral.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

## Commands to re-run

```sh
eval "$(luarocks path)"         # luv under /opt/lua-5.5 is found only this way
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
