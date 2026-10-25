<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Benchmarks follow-up: run the network scenarios on Windows (port `benchmarks/lib/runner.lua` to `reactor.spawn`), add the multi-process accept-spread scenario of ADR 0023, and publish the first baseline measured by the owner.
- status: in-progress
- lock_until: 2026-10-25T11:11:47Z
- last_update: 2026-10-25T09:41:47Z

## Done

- Claimed the item (#34 locked by another run; #35 and #38 wait on the owner).

## Next steps

1. Port `benchmarks/lib/runner.lua` (and run.lua/compare.lua callers) from popen/taskset/kill to `reactor.spawn`; keep pinning where `taskset` exists.
2. Accept-spread scenario (ADR 0023).
3. Docs, changelog, README of benchmarks; tick the roadmap except the owner-measured baseline.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

- The baseline must be measured by the owner on dedicated hardware.

## Commands to re-run

```sh
lua tools/run.lua bench tcp-echo
```
