<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `log`: structured logging, RFC 5424 severities, per-scope context.
- status: in-progress
- lock_until: 2026-10-21T11:11:11Z
- last_update: 2026-10-21T09:41:11Z

## Done

- Claimed. The `doc` item is held by #28 (locked until 11:30Z); #26 awaits owner review; next free item is `log`.

## Next steps

1. Read overview.md, concurrency.md, glossary, reactor context API (scope-local context).
2. Specify the log API (record, levels, Logger, sinks) and record gaps in open-questions.
3. Tests first, then implement; docs, README, CHANGELOG, roadmap tick.

## Decisions taken (and where they are recorded)

- Branch is the session-designated `claude/sweet-feynman-2jslka`, not `claude/relay-log`.

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua test log
```
