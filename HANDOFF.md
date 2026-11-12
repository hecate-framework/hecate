<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Examples: comment width and output placement (owner request, 2026-11-12).
- status: in-progress
- lock_until: 2026-11-13T02:10:00Z
- last_update: 2026-11-13T00:40:00Z

## Done

- Roadmap item and the two rules added to the phase gates ("It works").
- Taken up by the relay (2026-11-12): `main` merged in (7172c92); the Phase 2 gate (#183) is parked until this item is ticked.

- Step 1: `check-examples` (`tools/tasks/check_examples.lua`, `tools/lib/examples.lua`) and the shared runner
  `tools/harness/examples.lua` (rule 2), tested in `tools/tests/examples_test.lua`; catalogue row in `automation.md`,
  `CLAUDE.md`. Not yet in `ci.yml` (it would fail until the migration).
- Step 2: the `examples_test.lua` of the ten packages use the shared runner (http keeps its `-- Answers:` server path,
  net its TLS skip). The tests of config, container, http, router and schema now FAIL until step 3 (20 examples gather
  their output at the end). `examples/hello` is an application, not a printing example: only rule 1 applies to it.

- Step 3: every example migrated (both rules; 20 examples had gathered output, 98 lines over the width), website
  copies resynced (`check-docs-examples` ok), 4 inline website lines fixed; `check-examples` added to the `docs-checks`
  and static-check task lists of `ci.yml`; `documentation.md` "Code examples", `website/CLAUDE.md`, `CHANGELOG.md`.
  Local: every check ok, `test` ok (all packages, tools, examples/hello), `typecheck` ok. Only change of printed
  output: the container example shows the scope closing through `session.closed` (`true`) instead of a print from
  `__close`.

## Next steps

1. Watch CI of pull request #182 on the three platforms; fix any failure (Windows: line endings of examples read by
   the runner are handled; check `os.tmpname` in `tools/tests/examples_test.lua`).
2. When green: tick the roadmap item, delete this file, update the pull request body (implementation added), mark it
   ready for review and ask the owner for review. Then the Phase 2 gate (#183, parked) can resume after the merge.

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
