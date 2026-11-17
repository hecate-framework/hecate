<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Owner follow-up on PR #218 (2026-11-17): the Unicode packages (ADR 0032), the scope correction of `doc` (no API reference), Mermaid, and the audience split (OQ-144)
- status: in-progress
- lock_until: 2026-11-17T16:15:21Z
- last_update: 2026-11-17T14:45:21Z

## Done

- Step 1 (9faa749): `unicode` + `unicode-data` packages, Unicode 18.0.0, `gen-unicode`, `check-unicode-version`, fetch-fixtures `url`+`sha256`; OQ-140 resolved.
- Step 2 (db641e7): API reference removed from `doc`; OQ-141 resolved; stale reference-page lines of `openapi` fixed (OQ-135).

- ADR 0032 (Accepted by the owner, 2026-11-17); `www.unicode.org` allowed in the environment (reachable).

## Next steps

1. Mermaid (OQ-128): ADR `Proposed` for vendored browser libraries, vendored mermaid.js loaded only on pages with a diagram.
2. Audience split (OQ-144, issue #223, owner: "a key element"): front matter `audience` and filter; a project site publishes only what it is asked to; internal symbols out of the code reference by default.
3. Project documentation section title and wording in `documentation.md` (`generated for users` is ambiguous).

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
