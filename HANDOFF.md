# Handoff

- roadmap_item: `json` follow-up: libFuzzer C targets for the native code of `json`
- status: waiting-ci
- lock_until: 2026-10-26T02:17:13Z
- last_update: 2026-10-26T00:47:13Z

## Done

Targets `decode` and `decode_limits` (packages/json/csrc/fuzz), C support in the `fuzz` task, workflow artifact paths, docs, changelog, roadmap tick. Verified locally for 30 s per target.

## Next steps

1. Read CI of the PR (notably `fuzz (short)` and `sanitize`); fix failures.
2. When green: delete HANDOFF.md, mark ready for review, ask the owner for review. Never merge.

## Decisions taken (and where they are recorded)

The harness includes native.c and yyjson.c directly (no new ADR; no new dependency).

## Doubts and questions for the owner

None.

## Commands to re-run

```sh
lua tools/run.lua fuzz decode --seconds 30
lua tools/run.lua test tools
```
(needs libclang-rt-dev for the fuzzer runtime)
