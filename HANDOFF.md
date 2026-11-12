<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Examples: comment width and output placement (owner request, 2026-11-12).
- status: in-progress
- lock_until: 2026-11-12T16:30:00Z
- last_update: 2026-11-12T14:30:00Z

## Done

- Roadmap item and the two rules added to the phase gates ("It works").

## Next steps

1. `tools/tasks/check_examples.lua` (rule 1, exception marker on the line above), its tests in `tools/tests/`, added to the
   `docs-checks` and static-check task lists of `.github/workflows/ci.yml`, `automation.md`, `CLAUDE.md`.
2. Shared examples-test helper (rule 2: each printed or logged line expected by a `-- Prints:` block directly under the line
   that produced it); the `examples_test.lua` of every package uses it.
3. Migrate every example (`packages/*/examples/`, `examples/`) and the website pages that include them
   (`check-docs-examples`); fix comment lines over 80 characters.
4. `documentation.md`, `website/CLAUDE.md`, `CHANGELOG.md`; CI green on three platforms; tick, delete this file.

## Decisions taken (and where they are recorded)

- Started at the owner's request in a live session (not by the relay routine); the owner leaves the implementation open.

## Doubts and questions for the owner

## Commands to re-run

```sh
eval "$(luarocks path)"          # luv
lua tools/run.lua setup-luals    # once per session
lua tools/run.lua typecheck      # before every push
```
