<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `reactor` follow-up: scope-local context, `reactor.with_local(key, value, fn)` and `reactor.local(key)` (ADR 0025, OQ-55)
- status: waiting-ci
- lock_until: 2026-10-24T23:14:12Z
- last_update: 2026-10-24T21:44:12Z

## Done

- Claimed the item. #34 (CI workflows) is locked by another run; #31 waits on the owner.

- Specification, `reactor.with_local`/`local_value`, `log.bind` + default provider, tests, docs, changelog, roadmap ticked (local gates pass: test reactor, test log, lint, check-*).

## Next steps

1. Wait for CI on the three platforms; fix failures.
2. When green: delete HANDOFF.md, mark ready, ask the owner for review.

## Decisions taken (and where they are recorded)

- `local` is a Lua keyword: exposed as `reactor["local"]` and `reactor.local_value` (OQ-56, owner to decide).
- luv installed locally with `luarocks install --tree .hecate/rocks luv` to run tests.

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua test reactor
```
