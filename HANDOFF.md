<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `log`: structured logging, RFC 5424 severities, per-scope context.
- status: in-progress
- lock_until: 2026-10-22T23:10:15Z
- last_update: 2026-10-22T21:40:15Z

## Done

- Claimed. The `doc` item is held by #28 (locked until 11:30Z); #26 awaits owner review; next free item is `log`.
- Step 1: severities, `Record`, `Logger` (threshold, `with_context`, `context_provider`), `MemorySink`, `JsonLinesSink`, `Secret`; unit tests in `packages/log/tests/unit`; README and CHANGELOG updated; OQ-55 records the open points. Roadmap item NOT ticked.

- Step 2: merged main; `ConsoleSink` and synchronous `FileSink` with tests, README, CHANGELOG. Asynchronous flushing not started.

- Step 3 (investigation only): asynchronous flushing is blocked. A sink queue needs a wake for its drain task that never suspends the logging caller. `Condition:signal` requires entering the monitor (can suspend); `Channel:_try_send` is private. Needed from `reactor` (owner decision, cross-package): a public non-suspending wake, e.g. `Channel:try_send`/`try_receive`. Until then take next steps 2, 3, 5, 6 first.

- Step 4: `LimitedSink` (sampling, token-bucket rate limit, exempt severities) with tests, README, CHANGELOG. Next steps 2 done.

- Step 5: CI typecheck failed (8 undefined-field on `Severity:names/values/find/contains`); declared the enumeration operations on the `Severity` class annotation. LuaLS still not installed locally, CI is the check.

- Step 6 (owner go-ahead, 2026-10-22): the "blocked" claim was wrong; `AsyncSink` built on `Semaphore:release` and `reactor.detach` (tests pass), OQ-55 addendum corrected, ADR 0025 (`reactor.with_local` / `reactor.local`, Proposed) written, README and CHANGELOG updated.

## Next steps

1. Secret redaction beyond the marker (by field name, other sinks).
2. When ADR 0025 is accepted and implemented in `reactor`: default context provider in `log`, propagation test across fork/join.
3. Docs in `website/` (reference, how-to), examples in `packages/log/examples`, benchmark of a disabled and an enabled call (and of `AsyncSink`).
4. Run `typecheck` (CI), then tick the roadmap item and mark the PR ready. The item can also be ticked without 2 if the owner agrees.

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
