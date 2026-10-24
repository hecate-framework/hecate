<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Workflows `native.yml`, `security.yml`, `nightly.yml`; tasks `sanitize`, `fuzz`, `leaks`, `coverage`, `bench`, `check-licenses`.
- status: in-progress
- lock_until: 2026-10-24T21:05:26Z
- last_update: 2026-10-24T20:55:26Z

## Done

- Claimed the item (no open relay pull request had work left: #29 and #31 wait on the owner).
- Step 1 done: `bench` task already exists; missing tasks are `sanitize`, `fuzz`, `leaks`, `coverage`, `check-licenses` (spec: automation.md lines 46-60, 97-108). Existing workflows: ci, claude, docs, labels, pr-hygiene, security, website.

## Next steps

1. Read coding-standards.md (sanitizer, fuzz requirements) and packages/json csrc/native layout.
2. Implement the tasks `sanitize`, `fuzz`, `leaks`, `coverage`, `check-licenses` (tests first).
3. Add `native.yml`, `nightly.yml`; complete `security.yml` (CodeQL, dependency review, Scorecard).

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua --list
```
