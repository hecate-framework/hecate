<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Website: Diátaxis structure, English source, French locale enabled, MDN-like theme, getting-started tutorial, reference generated from annotations, built by `hecate doc` (ADR 0012, after OQ-11)
- status: in-progress            <!-- in-progress | waiting-ci | waiting-owner -->
<!-- Optional, only when the owner holds this pull request for one run: - owner: session `<session id>`, why. -->
- lock_until: 2026-11-26T20:45:00Z
- last_update: 2026-11-26T18:42:00Z

## Done

- French reference index brought in step with the English one (commit: see branch log).
- Six `http` pages translated into French (`explanation/http-model`, five how-tos) with the glossary terms; `serve-http` links the English `map-domain-errors-to-problem-details` until that page is translated.

## Next steps

1. Translate the other English-only pages, then the remaining sub-items of the roadmap item.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
