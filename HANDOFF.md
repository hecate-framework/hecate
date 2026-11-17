<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Owner follow-up on PR #218 (2026-11-17): the Unicode packages (ADR 0032), the scope correction of `doc` (no API reference), Mermaid, and the audience split (OQ-144)
- status: in-progress
- lock_until: 2026-11-17T20:30:00Z
- last_update: 2026-11-17T19:05:00Z

## Done

- Step 3: audiences (OQ-144, conservative implementation) and Mermaid (ADR 0033 Proposed, OQ-128).

- Step 1 (9faa749): `unicode` + `unicode-data` packages, Unicode 18.0.0, `gen-unicode`, `check-unicode-version`, fetch-fixtures `url`+`sha256`; OQ-140 resolved.
- Step 2 (db641e7): API reference removed from `doc`; OQ-141 resolved; stale reference-page lines of `openapi` fixed (OQ-135).

- ADR 0032 (Accepted by the owner, 2026-11-17); `www.unicode.org` allowed in the environment (reachable).

## Next steps

1. (done) CI green on the three platforms at d0cbd0a (macOS needed one re-run after a runner-queue cancellation).
2. Final pass: roadmap items ticked/unticked coherent, `/review-package doc` (reviewers), then ask the owner for review (mark ready only when the owner's follow-ups are all done).

## Decisions taken (and where they are recorded)

- NFC route: ADR 0032 (Accepted).
- OQ-141: closes with step 2 (no API reference in `doc`).

## Doubts and questions for the owner

- None blocking.

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
