<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Owner follow-up on PR #218 (2026-11-17): Unicode normalisation of page ids (OQ-140): a `unicode` code package and a data rock `unicode-data` versioned by Unicode version, with a Proposed ADR
- status: in-progress            <!-- in-progress | waiting-ci | waiting-owner -->
<!-- Optional, only when the owner holds this pull request for one run: - owner: session `<session id>`, why. -->
- lock_until: 2026-11-17T14:39:54Z
- last_update: 2026-11-17T13:09:54Z

## Done

- ADR 0032 (Proposed): `unicode` + `unicode-data` packages, layer 0; OQ-140 updated.

## Next steps

1. Scaffold both packages (`lua tools/run.lua new-package`), generator `gen-unicode`, NFC/NFD, tests against NormalizationTest.txt (`fetch-fixtures`).
2. Replace the Latin table of `hecate.doc.internal.page_id` by `hecate.unicode`; update OQ-140 and issue #219, README, CHANGELOG, website reference, roadmap.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
