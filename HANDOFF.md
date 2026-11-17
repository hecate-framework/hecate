<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Owner follow-up on PR #218 (2026-11-17): Unicode normalisation of page ids (OQ-140): a `unicode` code package and a data rock `unicode-data` versioned by Unicode version, with a Proposed ADR
- status: waiting-owner            <!-- in-progress | waiting-ci | waiting-owner -->
<!-- Optional, only when the owner holds this pull request for one run: - owner: session `<session id>`, why. -->
- lock_until: 2026-11-17T13:10:04Z
- last_update: 2026-11-17T13:10:04Z

## Done

- ADR 0032 (Proposed): `unicode` + `unicode-data` packages, layer 0; OQ-140 updated.

## Next steps

1. Scaffold both packages (`lua tools/run.lua new-package`), generator `gen-unicode`, NFC/NFD, tests against NormalizationTest.txt (`fetch-fixtures`).
2. Replace the Latin table of `hecate.doc.internal.page_id` by `hecate.unicode`; update OQ-140 and issue #219, README, CHANGELOG, website reference, roadmap.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

- BLOCKED: `www.unicode.org` (UCD files `UnicodeData.txt`, `DerivedNormalizationProps.txt`, `NormalizationTest.txt` under `/Public/<version>/ucd/`, and `/Public/UCD/latest/ReadMe.txt` for the nightly check) is refused by the cloud egress proxy (`curl https://www.unicode.org/Public/UCD/latest/ReadMe.txt` -> CONNECT 403). Allow the domain (ADR 0032 notes it for `tools/cloud/README.md`), then the next run scaffolds the packages and runs `gen-unicode`. Not worked around: no data taken from another source.

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
