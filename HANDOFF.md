<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Website skeleton in `website/en` with the Hecate visual identity (docs for `net` and the new reactor primitives owed)
- status: in-progress
- lock_until: 2026-10-19T00:00:34Z
- last_update: 2026-10-18T22:30:34Z

## Done

- Claimed the item (PR #19 `net`/website CI merged; no other relay PR open).

## Next steps

1. Run `lua tools/run.lua gen-reference` and check the generated `core`, `reactor`, `net` pages build.
2. Hand-written `net` how-to guides with the `docs-writer` agent (TCP, TLS, deadlines, UDP/pipes, child processes).
3. Explanations (transport model, back-pressure, TLS defaults ADR 0024, multi-process ADR 0023).
4. Update `website/OUTLINE.md` and `llms.txt`; then French pages (`translator-fr`).

## Decisions taken (and where they are recorded)

None yet.

## Doubts and questions for the owner

None yet.

## Commands to re-run

```sh
lua tools/run.lua --list
```
