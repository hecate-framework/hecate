# 0016 — AI-assisted development with Claude Code agents

- **Status:** Accepted
- **Date:** 2026-10-11
- **Deciders:** project owner
- **Packages:** all
- **Related:** [ai-assisted-development.md](../architecture/ai-assisted-development.md), `CLAUDE.md`, `.claude/`

## Context

Implementation is delegated to Claude Code. Quality depends on the context given to
agents: specifications, conventions, boundaries and verification steps.

## Decision

- Root `CLAUDE.md` (and `AGENTS.md` pointing to it) define rules and workflow.
- Every package has a `packages/<name>/CLAUDE.md` loaded when working inside it.
- `.claude/agents/` defines one specialist subagent per package plus cross-cutting
  reviewers (architecture, terminology, documentation, translation, tests,
  performance, security, native code, cross-platform, CI, release).
- `.claude/commands/` provides repeatable workflows (implement a task, review a package,
  draft an ADR, translate a page, run a spike, prepare a release).
- `llms.txt` at the root and on the website gives LLMs a map of the documentation.
- Agents never mark an ADR `Accepted`; only the project owner does.

## Verification

Pull requests produced by agents follow the same template and CI as human ones.
