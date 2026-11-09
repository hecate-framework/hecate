<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `kernel`: application, modules, controllers, route modules, filters, problem details, lifecycle, multi-process workers, graceful shutdown (Phase 2, docs/roadmap.md)
- status: in-progress
- lock_until: 2026-11-09T11:49:38Z
- last_update: 2026-11-09T10:19:38Z

## Done

- Claimed the item (previous relay branch was already merged into main via PR #162/#165).

## Next steps

1. First step of the item: split `packages/http/src/hecate/http/server.lua` (options, response writer, connection) and `client.lua` (pool, redirect) with no API change.
2. In-process dispatch seam (OQ-78, OQ-76 a), `on_response` hook (OQ-81), remove the JSON fallback of `Server` for a table (OQ-76 a), default logger (OQ-79, `log.default()`), narrow `Request.content`.
3. OQ-101 items (a) `json.set_max_depth`, (b) logging keys, (c) `wrap_secret`.
4. Settle how a route names its response schema (OQ-98 item 7), then the kernel proper.

## Decisions taken (and where they are recorded)

- Worked on the session-designated branch `claude/sweet-feynman-h1j6tu` instead of `claude/relay-kernel` (session instruction). No pull request opened: none was requested.

## Doubts and questions for the owner

- The run was triggered by a bare "Retry" message with no task text; I assumed the relay routine and started the first unchecked roadmap item.

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
