<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `core`: object model (classes, traits, interfaces, conformance), error hierarchy, enumerations, compatibility shims
- status: in-progress            <!-- in-progress | waiting-ci | waiting-owner -->
- lock_until: 2026-10-12T20:52:09Z
- last_update: 2026-10-12T19:22:09Z

## Done

- Claimed the item (Phase 0 complete, PR #16 merged).
- Step 1 done: compat, class/trait/interface/finalise, introspection, Error hierarchy with tests (packages/core/tests/unit).

## Next steps

1. Step 2: enumeration and value_class (tests first; add both to the rockspec modules).
2. Step 3: README Public API/status, CHANGELOG, ADR 0007 final spelling, open questions, micro-benchmark, website page if structure exists.

## Decisions taken (and where they are recorded)

- Declaration spelling: `core.class(name, parent, {traits=, implements=})`, methods by assignment, `core.finalise(C)` (to be recorded in ADR 0007 in step 3).

## Doubts and questions for the owner

## Commands to re-run

```sh
```
