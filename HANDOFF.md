<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Benchmarks follow-up: add the multi-process accept-spread scenario of ADR 0023 (connections per second and worker spread per strategy), and publish the first baseline measured by the owner.
- status: in-progress
- lock_until: 2026-10-25T17:20:00Z
- last_update: 2026-10-25T15:50:00Z

## Done

- Claimed the item. #34 (CI native/security/nightly) is locked by another run until 2026-10-25T12:51:26Z, so it was skipped; PR #37 is a Dependabot bump (not relay).
- Found: `spikes/OQ-8/` (the earlier spread measurement) is git-ignored and absent from this checkout; the scenario must be rewritten from ADR 0023 and the reactor multi-process API (`packages/reactor/src/hecate/reactor/{process,ipc}.lua`). luv is not installed here: `luarocks --tree .hecate/rocks install luv 1.53.0-0`.

## Progress (resumed 2026-10-25 15:40Z)

- Scenario `benchmarks/scenarios/accept-spread/` written and run locally (round_robin 4 workers: spread 1.00, reuseport skipped); runner `--server-args`, control port, skipped; tests, README, CHANGELOG done.
- The roadmap item stays unchecked: the baseline is the owner's.

## Next steps (superseded)

1. Read ADR 0023 and the reactor spawn/ipc/reuseport API; install luv.
2. Scenario `benchmarks/scenarios/accept-spread/` (`server.lua` primary + workers, strategies `round_robin` and `reuseport` when supported; `load.lua` opens connections at a set rate, workers report accepts so the spread is max/mean).
3. Document in benchmarks/README.md; tests for the spread computation; CHANGELOG; leave the baseline to the owner.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

- `reuseport` cannot run until luv supports it (OQ-43): the scenario will report it as skipped.

## Commands to re-run

```sh
lua tools/run.lua --list
```
