<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `http`: HTTP/1.1 server (llhttp, OQ-6) and client, message model, streaming, keep-alive, limits (Phase 2)
- status: in-progress
- lock_until: 2026-11-01T14:15:04Z
- last_update: 2026-11-01T12:45:04Z

## Done

- Claimed the item after the Phase 1 gate merge (PR #47).

## Next steps

1. Read docs/architecture/http-and-routing.md, ADR 0019, spike OQ-6, packages/http/CLAUDE.md.
2. Plan the steps (message model, llhttp binding, server, client, limits, the three deferred Phase 1 findings) and record them here.
3. Message model first (fields, media types, Request/Response), tests first.

## Decisions taken (and where they are recorded)

None yet.

## Doubts and questions for the owner

None yet.

## Commands to re-run

```sh
lua tools/run.lua test http
```
