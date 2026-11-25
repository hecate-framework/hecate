# `hecate-actions`

> GitHub Actions of the project, used by the workflows that `hecate generate workflow` writes: `setup` installs the `hecate` executable of a release.

| | |
|---|---|
| Module | none (not a Lua rock) |
| Rock | none |
| Kind | actions |
| Layer | none (outside the Lua layers) |
| Roadmap phase | 3 |
| Status | alpha — `setup` (composite action: downloads the release, verifies its SHA-256, puts `hecate` on the `PATH`); the pin of its tag in the generated workflows and the first release are owner gates (OQ-149) |
| Depends on | — |
| Used by | `cli` (`hecate generate workflow` writes `uses: hecate-framework/hecate-actions/setup@<ref>`) |
| Native code | none |
| Specification | [cli-and-packaging.md](../../docs/architecture/cli-and-packaging.md) |
| Decisions | [ADR 0017](../../docs/adr/0017-monorepo-with-read-only-mirrors.md) |
| Agent | [`pkg-actions`](../../.claude/agents/pkg-actions.md) |
| Repository | read-only mirror `hecate-framework/hecate-actions`, generated from this directory (ADR 0017) |

## Responsibilities

- one directory per action, each with an `action.yml` at its root: `setup/` today
- the mirror has the same layout as this directory, so that GitHub resolves `hecate-framework/hecate-actions/<directory>@<ref>`
  to `<directory>/action.yml`; the `action.yml` files never move
- the README of each action documents its inputs and outputs

## Non-goals

- Lua code: this package is not a rock. It has no rockspec, no module and no `tests/` directory; the tools exempt it
  through the `Kind` row above (`tools/lib/package_kind.lua`), and `check-package-structure` still verifies its files
- the workflows of the project itself (`.github/workflows/`), which only call `tools/run.lua` tasks

## Standards and references

- GitHub Actions metadata syntax for composite actions

## Public API

```yaml
- uses: hecate-framework/hecate-actions/setup@<ref>
  with:
    version: "0.4.0-1"
```

See [`setup/README.md`](setup/README.md) for the inputs and outputs.
