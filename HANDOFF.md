<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Owner follow-up on PR #218 (2026-11-17): the Unicode packages (ADR 0032), the scope correction of `doc` (no API reference), Mermaid, and the audience split (OQ-144)
- status: in-progress
- lock_until: 2026-11-17T15:51:19Z
- last_update: 2026-11-17T14:21:19Z

## Done

- ADR 0032 (Accepted by the owner, 2026-11-17); `www.unicode.org` allowed in the environment (reachable).

## Next steps

1. `unicode` + `unicode-data` packages per ADR 0032 (scaffold, `gen-unicode`, `url`+`sha256` entry in `fetch-fixtures`, NormalizationTest.txt conformance, nightly `unicode-version`, replace the Latin table of `hecate.doc.internal.page_id`, close OQ-140 / #219).
2. `doc` scope correction (owner, 2026-11-17): the generator does NOT produce an API reference (route table, per-tag pages): the OpenAPI contract is external documentation and its viewer is the user's wiring. Remove `api_pages` and the `document` option, fix `documentation.md`, resolve OQ-141 (obsolete), README, CHANGELOG. Configuration reference: keep for now, to be sourced from the application, owner to confirm (asked why a JSON Schema is passed).
3. Mermaid (OQ-128): ADR `Proposed` for vendored browser libraries, vendored mermaid.js loaded only on pages with a diagram.
4. Audience split (OQ-144, issue #223, owner: "a key element"): front matter `audience` and filter; a project site publishes only what it is asked to; internal symbols out of the code reference by default.
5. Project documentation section title and wording in `documentation.md` (`generated for users` is ambiguous).

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
