<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `core`: object model (classes, traits, interfaces, conformance), error hierarchy, enumerations, compatibility shims
- status: waiting-ci            <!-- in-progress | waiting-ci | waiting-owner -->
- lock_until: 2026-10-12T20:56:15Z
- last_update: 2026-10-12T19:26:15Z

## Done

- Claimed the item (Phase 0 complete, PR #16 merged).
- Step 1: compat, class/trait/interface/finalise, introspection, Error hierarchy, tests.
- Step 2: enumeration, value_class, no-globals test, dispatch benchmark, rockspec modules.
- Step 3: README Public API/status, CHANGELOG, ADR 0007 final spelling section, OQ-19..21.
- Step 4: typecheck fixes (LuaLS 3.19.1, zero diagnostics locally).
- All tests (8 files) and the checks (lint, boundaries, glossary, rockspecs, package-structure, changelog, links) pass.

## Next steps

1. Run reviewers (/review-package core, api-reviewer, terminology-reviewer) and fix findings.
2. typecheck passes locally with LuaLS 3.19.1 (spikes/luals, git-ignored). Remaining: examples/ snippets; website reference is generated.
3. Owner: do not tick roadmap yet; review OQ-19..21 and freeze spelling in ADR 0007.

## Decisions taken (and where they are recorded)

- Declaration spelling: `core.class(name, parent, {traits=, implements=})`, methods by assignment, `core.finalise(C)` (to be recorded in ADR 0007 in step 3).

## Doubts and questions for the owner

## Commands to re-run

```sh
```

## Relay status (update)

- Implementation pushed; fixed markdownlint blank line in ADR 0007. Waiting for CI on three platforms.
- Remaining before ready-for-review: run `/review-package core` (reviewers), `typecheck` when LuaLS exists, tick roadmap, delete HANDOFF.md, comment for owner review (OQ-19..21, ADR 0007 spelling freeze).
