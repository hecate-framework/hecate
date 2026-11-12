<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Examples: comment width and output placement (owner request, 2026-11-12).
- status: in-progress
- lock_until: 2026-11-13T01:35:00Z
- last_update: 2026-11-13T00:05:00Z

## Done

- Roadmap item and the two rules added to the phase gates ("It works").
- Taken up by the relay (2026-11-12): `main` merged in (7172c92); the Phase 2 gate (#183) is parked until this item is ticked.

- Step 1: `check-examples` (`tools/tasks/check_examples.lua`, `tools/lib/examples.lua`) and the shared runner
  `tools/harness/examples.lua` (rule 2), tested in `tools/tests/examples_test.lua`; catalogue row in `automation.md`,
  `CLAUDE.md`. Not yet in `ci.yml` (it would fail until the migration).

## Next steps

1. The `examples_test.lua` of every package (config, container, core, http, json, log, net, reactor, router, schema)
   and the `examples/hello` tests use `tools/harness/examples.lua` (`examples.check(self, directory, NAMES, globals)`;
   http keeps its `-- Answers:` server path).
2. Migrate every example (`packages/*/examples/`, `examples/`) and the website pages that include them
   (`check-docs-examples`); fix the 98 lines reported by `check-examples` (94 in example files, 4 in website pages).
   Then add `check-examples` to the `docs-checks` (line ~144) and static-check (line ~485) task lists of `ci.yml`.
3. `documentation.md`, `website/CLAUDE.md`, `CHANGELOG.md`; CI green on three platforms; tick, delete this file.

## Decisions taken (and where they are recorded)

- Exemption marker: a comment holding `check-examples: allow-long-comment` on the line just above (`automation.md`).
- Width counted in UTF-8 characters; a long comment (`--[[ ]]`) counts on every line it spans; website blocks preceded
  by `<!-- example: -->` are checked through their file.
- Rule 2 attribution: each `print` belongs to the innermost line of the example running when it is called; a block takes
  the output of exactly one line; only the rest of that statement (no blank or comment line) may stand between them.
  A print inside a helper function defined earlier would be attributed to the helper: examples print inline.

- Started at the owner's request in a live session (not by the relay routine); the owner leaves the implementation open.

## Doubts and questions for the owner

## Commands to re-run

```sh
eval "$(luarocks path)"          # luv
lua tools/run.lua setup-luals    # once per session
lua tools/run.lua typecheck      # before every push
```
