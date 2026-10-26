# 0015 — CI/CD on GitHub Actions, tasks in Lua

- **Status:** Accepted
- **Date:** 2026-10-11
- **Deciders:** project owner
- **Packages:** repository-wide
- **Related:** [automation.md](../architecture/automation.md)

## Decision

- GitHub Actions for CI and CD. Workflows stay thin: they call repository tasks.
- Repository tasks live in `tools/` and are written in **Lua 5.5** (dogfooding, one
  language, cross-platform). Shell or PowerShell only for bootstrap steps that run
  before Lua exists.
- Every check that CI performs can be run locally with the same task
  (`lua tools/run.lua <task>`).
- Third-party actions are pinned by commit SHA in release workflows; Dependabot keeps
  them current.

## Verification

`ci.yml` invokes only `tools/` entry points; reviewed by the `ci-engineer` agent.
