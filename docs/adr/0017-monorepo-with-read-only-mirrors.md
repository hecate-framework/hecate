# 0017 — Monorepo for development, read-only mirror per package for distribution

- **Status:** Accepted
- **Date:** 2026-10-11
- **Deciders:** project owner
- **Packages:** all
- **Related:** ADR 0005, ADR 0016, [versioning-and-distribution.md](../architecture/versioning-and-distribution.md#repositories), [automation.md](../architecture/automation.md)

## Context

The owner wants each component to live in its own repository (visibility, lightweight
clones, rocks built from small sources). Splitting *development* across repositories
would break atomic cross-package changes, complicate lockstep versioning (ADR 0005) and
degrade AI-assisted work (ADR 0016): Claude Code loads nested `CLAUDE.md` files on
demand inside one tree, whereas sibling repositories added with `--add-dir` do not load
their `CLAUDE.md` files by default and cannot be changed atomically.

## Options considered

1. **Polyrepo**: one repository per package for development. Atomicity lost, shared
   context (ADRs, glossary, agents, tools) duplicated or centralised in a meta
   repository.
2. **Monorepo only.** Simplest; no per-component repositories.
3. **Monorepo + read-only mirrors** (Symfony model): development, issues and pull
   requests in the monorepo; each package is split automatically into its own
   repository with its own history and the same tags.

## Decision

Option 3.

- Development repository: `hecate-framework/hecate` (the monorepo). The only place for issues,
  pull requests, discussions and CI.
- One read-only mirror per package, named after its rock: `hecate-framework/hecate-<name>`
  (e.g. `hecate-router`). The meta-rock `hecate` is built from the monorepo itself.
- Mirrors are updated by the `split` task on every push to `main` (branch `main`) and on
  every release tag (same tag `vX.Y.Z` in every mirror).
- Mirrors have issues, wiki and projects disabled; an automated workflow closes pull
  requests with a message pointing to the monorepo; their README states that they are
  read-only.
- Released rockspecs take their sources from the mirror at the release tag; `scm`
  rockspecs point to the mirror's `main`.
- Separate, non-mirror repositories only where a platform requires them: Homebrew tap
  (`hecate-framework/homebrew-hecate`) and Scoop bucket (`hecate-framework/scoop-hecate`), updated by the
  release pipeline. Third-party drivers or extensions may live in their own repositories
  later.
- Nobody, human or agent, commits to a mirror directly.

The organisation is `hecate-framework` (OQ-10, resolved).

## Consequences

- Users see one repository per component; contributors and agents work in one tree.
- Release tooling must create mirrors, push splits, tag them and keep their settings
  consistent (`check-mirrors`).
- The split must be deterministic so that mirror histories are stable across runs
  (tool choice: OQ-17).

## Verification

`split.yml` runs on `main` and tags; `check-mirrors` (nightly) verifies that each
mirror's `main` and tags match the split of the monorepo and that settings are correct.
