<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `log`: structured logging, RFC 5424 severities, per-scope context.
- status: in-progress
- lock_until: 2026-10-23T14:20:00Z
- last_update: 2026-10-23T12:50:00Z

## Done

- Claimed. The `doc` item is held by #28 (locked until 11:30Z); #26 awaits owner review; next free item is `log`.
- Step 1: severities, `Record`, `Logger` (threshold, `with_context`, `context_provider`), `MemorySink`, `JsonLinesSink`, `Secret`; unit tests in `packages/log/tests/unit`; README and CHANGELOG updated; OQ-55 records the open points. Roadmap item NOT ticked.

- Step 2: merged main; `ConsoleSink` and synchronous `FileSink` with tests, README, CHANGELOG. Asynchronous flushing not started.

- Step 3 (investigation only): asynchronous flushing is blocked. A sink queue needs a wake for its drain task that never suspends the logging caller. `Condition:signal` requires entering the monitor (can suspend); `Channel:_try_send` is private. Needed from `reactor` (owner decision, cross-package): a public non-suspending wake, e.g. `Channel:try_send`/`try_receive`. Until then take next steps 2, 3, 5, 6 first.

- Step 4: `LimitedSink` (sampling, token-bucket rate limit, exempt severities) with tests, README, CHANGELOG. Next steps 2 done.

- Step 5: CI typecheck failed (8 undefined-field on `Severity:names/values/find/contains`); declared the enumeration operations on the `Severity` class annotation. LuaLS still not installed locally, CI is the check.

- Step 6 (2026-10-22T18:50Z, new run, lock had expired, CI was green): how-to guide `website/en/how-to/log-structured-records.md`, tested examples in `packages/log/examples`. Next steps 5 partly done (reference page and benchmark remain).

- Step 7 (owner go-ahead, 2026-10-22): the "blocked" claim was wrong; `AsyncSink` built on `Semaphore:release` and `reactor.detach` (tests pass), OQ-55 addendum corrected, ADR 0025 (`reactor.with_local` / `reactor.local`, Proposed) written, README and CHANGELOG updated.

- Step 10 (2026-10-23T12:50Z, new run on `claude/sweet-feynman-pwytm6`, locks expired; main already merged): `log` added to `reference_site.DEFAULT_PACKAGES` (reference generated in CI, LuaLS not installed here), benchmark `packages/log/benchmarks/logger.lua` (disabled ~115 ns, enabled ~1.7 us). Local gates ok; `test doc` fails locally only because the Rust native module is not built (same on main). Remaining: CI typecheck and reference build green, then tick the roadmap item (ADR 0025 default context provider can follow).

## Next steps

1. (done, Logger option `redact`) Secret redaction by field name; remaining: redaction in sinks other than the JSON lines one, if wanted.
2. When ADR 0025 is accepted and implemented in `reactor`: default context provider in `log`, propagation test across fork/join.
3. Reference page in `website/`, how-to for `AsyncSink`, benchmark of a disabled and an enabled call (and of `AsyncSink`).
4. Run `typecheck` (CI), then tick the roadmap item and mark the PR ready. The item can also be ticked without 2 if the owner agrees.

- Step 8 (parallel session, merged here; resumed 2026-10-22, work pushed on the session branch `claude/sweet-feynman-ycyozt`, which carries the PR #29 history): merged main; `Logger` option `redact` (step 3 done, by field name; other sinks already redact `Secret`) with tests.

- Step 9 (2026-10-23, new run on session branch `claude/sweet-feynman-w6qist`, locks had expired; merged main): how-to section and tested example for `AsyncSink`. Remaining: reference page, benchmark, typecheck in CI, tick.

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
