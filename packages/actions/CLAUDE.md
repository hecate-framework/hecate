# Agent context — `hecate-actions`

You are working inside `packages/actions`. Read the root `CLAUDE.md` first; this file adds
package-specific context. Specialist agent: `pkg-actions`.

## Purpose

GitHub Actions of the project, used by the workflows that `hecate generate workflow` writes. Not a Lua rock.

## Read before changing anything

- Specification: `docs/architecture/cli-and-packaging.md` (the setup action, the generated workflows)
- Decisions: `docs/adr/0017-monorepo-with-read-only-mirrors.md`
- Glossary: `docs/glossary.md`
- This package's `README.md` (scope, status)

## Boundaries

- No Lua code, no rockspec, no `tests/`: the package has `Kind | actions` in its README, which exempts it from the
  rockspec, version and layer checks (`tools/lib/package_kind.lua`).
- The mirror `hecate-framework/hecate-actions` is the directory itself: keep every `action.yml` at `<directory>/action.yml`.
  Renaming or moving one breaks the `uses:` line of every project that pins it.
- A third-party action referenced by an action here is pinned by commit SHA with a version comment, and runs on `node24`
  or later (or is composite or Docker).
- If your task needs a change in another package, stop and describe it instead of making it.

## Invariants (must hold after every change)

- `setup` verifies the SHA-256 of the executable before installing anything
- the `X.Y.Z-R` form of the `version` input is the only one accepted
- every action has a README that lists its inputs and outputs

## Test strategy

- the generated workflows are tested in `packages/cli` (`generate_workflow_test.lua`) and end to end in `tools/tests/cli_e2e_test.lua`
- `check-package-structure` verifies the files of the package

## Standards

- GitHub Actions metadata syntax
