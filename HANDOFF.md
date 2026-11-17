<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Owner follow-up on PR #218 (2026-11-17): Unicode normalisation of page ids (OQ-140): a `unicode` code package and a data rock `unicode-data` versioned by Unicode version, with a Proposed ADR
- status: in-progress            <!-- in-progress | waiting-ci | waiting-owner -->
<!-- Optional, only when the owner holds this pull request for one run: - owner: session `<session id>`, why. -->
- lock_until: 2026-11-17T14:37:28Z
- last_update: 2026-11-17T13:07:28Z

## Done

## Next steps

1. Write the Proposed ADR (new `unicode` package at the lowest fitting layer + data rock `hecate-unicode-data` versioned by Unicode version, minimum-version dependency, Unicode License v3 notice, pinned version, generator task, nightly newer-version check).
2. Scaffold both packages (`lua tools/run.lua new-package`), generator `gen-unicode`, NFC/NFD, tests against NormalizationTest.txt (`fetch-fixtures`).
3. Replace the Latin table of `hecate.doc.internal.page_id` by `hecate.unicode`; update OQ-140 and issue #219, README, CHANGELOG, website reference, roadmap.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
