<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `log`: structured logging, RFC 5424 severities, per-scope context.
- status: in-progress
- lock_until: 2026-10-21T11:14:16Z
- last_update: 2026-10-21T09:44:16Z

## Done

- Claimed. The `doc` item is held by #28 (locked until 11:30Z); #26 awaits owner review; next free item is `log`.
- Step 1: severities, `Record`, `Logger` (threshold, `with_context`, `context_provider`), `MemorySink`, `JsonLinesSink`, `Secret`; unit tests in `packages/log/tests/unit`; README and CHANGELOG updated; OQ-55 records the open points. Roadmap item NOT ticked.

## Next steps

1. Console (human) and file sinks; asynchronous flushing with back-pressure (test strategy: sink back-pressure) without suspending the caller.
2. Sampling and rate limiting.
3. Secret redaction beyond the marker (by field name, other sinks).
4. Replace the `context_provider` workaround once `reactor` has scope-local context (OQ-55, needs the owner and a `reactor` change); then test propagation across fork/join through it.
5. Docs in `website/` (reference, how-to), examples in `packages/log/examples`, benchmark of a disabled and an enabled call.
6. Run `typecheck` (LuaLS was not installed in this session), then tick the roadmap item and mark the PR ready.

## Decisions taken (and where they are recorded)

- Branch is the session-designated `claude/sweet-feynman-2jslka`, not `claude/relay-log`.
- Conservative choices of step 1 are listed in OQ-55 (docs/open-questions.md).

## Doubts and questions for the owner

- OQ-55: `reactor` needs a documented per-scope context API for implicit propagation.

## Commands to re-run

```sh
export LUA_CPATH="/opt/lua-5.5/lib/lua/5.5/?.so;;"   # luv for the reactor-based test
lua tools/run.lua test log
```
