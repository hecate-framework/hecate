<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Workflows `native.yml`, `security.yml`, `nightly.yml`; tasks `sanitize`, `fuzz`, `leaks`, `coverage`, `bench`, `check-licenses`.
- status: in-progress
- lock_until: 2026-10-25T10:02:23Z
- last_update: 2026-10-25T08:32:23Z

## Done

- Claimed the item (no open relay pull request had work left: #29 and #31 wait on the owner).
- Step 1 done: `bench` task already exists; missing tasks are `sanitize`, `fuzz`, `leaks`, `coverage`, `check-licenses` (spec: automation.md lines 46-60, 97-108). Existing workflows: ci, claude, docs, labels, pr-hygiene, security, website.

- Step 2 done: `sanitize` task (tools/lib/sanitize.lua, tests, HECATE_SANITIZE in build-native), verified locally on json. #29 merged; #31 waits on the owner.

- Step 3 done: `check-licenses` task (tools/lib/licenses.lua, tests).

- Step 4 done: `fuzz` task (tools/lib/fuzz.lua, tests) wrapping the cargo-fuzz targets of net; json C libFuzzer target still to write.

- Step 5 done: `leaks` task (tools/lib/leaks.lua, harness `on_finish` hook, `HECATE_TEST_LEAKS` in run_file.lua, tests). Verified with luv installed (`luarocks --tree .hecate/rocks install luv 1.53.0-0`): it found a handle leaked by the net tcp test spy helper (fixed); `leaks`, reactor and net tests pass.

- Merged origin/main (conflicts in CHANGELOG.md and automation.md resolved).

## Next steps

1. Implement the task `coverage` (debug-hook LCOV, thresholds core/reactor/router/schema >= 90 %, tests first); json libFuzzer C target.
2. Add `native.yml`, `nightly.yml`; complete `security.yml` (CodeQL, dependency review, Scorecard).

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua --list
```
