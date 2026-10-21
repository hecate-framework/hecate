<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `doc` (minimal) and the reference generator, pulled forward from Phase 3 (ADR 0012, OQ-11)
- status: in-progress            <!-- in-progress | waiting-ci | waiting-owner -->
- lock_until: 2026-10-21T11:10:00Z
- last_update: 2026-10-21T09:40:00Z

## Done

- Claimed. #25 (`json`) is merged; `doc` already has a first slice (renderer, site model, theme, search, reference generator).

## Next steps

1. Move `doc` onto `hecate.json` (remove `hecate.doc.internal.json`), OQ-33 (b) `reactor.fs` next.
2. Integrate the ADR 0022 native module (comrak, syntect) in steps.
3. Reference pages for `core` and `reactor`; website built by `doc` in CI.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

## Commands to re-run

```sh
```
