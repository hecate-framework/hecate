# AI-assisted development

Status: [ADR 0016](../adr/0016-ai-assisted-development.md) (Accepted).

Hecate is implemented primarily by Claude Code under the owner's supervision. This
document explains how context, agents and commands are organised so that work stays
consistent across hundreds of sessions.

## Context files

| File | Loaded | Content |
|---|---|---|
| `CLAUDE.md` | always | rules, sources of truth, workflow, definition of done, commands |
| `AGENTS.md` | by other agent tools | points to `CLAUDE.md` |
| `packages/<name>/CLAUDE.md` | when working in that package | scope, boundaries, invariants, standards, test strategy, pitfalls |
| `website/CLAUDE.md` | when working on the website | writing rules, i18n process |
| `tools/CLAUDE.md` | when working on scripts | task conventions |
| `llms.txt` | external LLMs | map of documentation |

Keep these files short and factual; link to specifications instead of duplicating them.
When a specification changes, update the affected CLAUDE.md in the same commit.

## Agents (`.claude/agents/`)

### Package specialists

One agent per package: `pkg-<name>`. Each knows its package's scope, dependencies,
standards (RFCs, protocols), invariants and test strategy, and must refuse to modify
other packages beyond what its task requires (it reports needed changes instead).

### Cross-cutting agents

| Agent | Role |
|---|---|
| `architect` | guards layering, ADR consistency and public API design; drafts ADRs |
| `terminology-reviewer` | enforces the glossary (ADR 0004) |
| `api-reviewer` | reviews public API ergonomics and consistency across packages |
| `test-engineer` | test design, property tests, fixtures, coverage gaps |
| `performance-engineer` | benchmarks, profiling, hot paths, allocation reduction |
| `security-reviewer` | input handling, protocol parsing, TLS, authentication, supply chain |
| `native-code-reviewer` | C code: memory safety, Lua C API usage, portability, sanitizers |
| `cross-platform-reviewer` | Windows/macOS/Linux differences, paths, line endings, sockets |
| `docs-writer` | website pages following Diátaxis and the writing rules |
| `translator-fr` | French translation of website pages, glossary-consistent terminology |
| `ci-engineer` | workflows and `tools/` scripts (ADR 0015) |
| `release-manager` | release preparation and verification |
| `dx-reviewer` | judges changes from the user's point of view against developer-experience.md |

## Commands (`.claude/commands/`)

| Command | Purpose |
|---|---|
| `/implement-task <roadmap item>` | end-to-end implementation workflow |
| `/new-adr <topic>` | draft a `Proposed` ADR |
| `/new-package <name>` | scaffold a package with all context files |
| `/review-package <name>` | full review by the relevant specialists |
| `/spike <question>` | time-boxed research answering an open question, written up in `docs/spikes/` |
| `/check` | run every local quality gate and summarise |
| `/translate <page> <locale>` | translate or refresh a website page |
| `/write-docs <package>` | write or update the website pages of a package |
| `/bench <scenario>` | run and interpret benchmarks |
| `/prepare-release <version>` | release checklist |
| `/relay` | one unit of autonomous, resumable work (see "Relay" below) |

## Working modes

- **One roadmap item per session or per branch.** Large items are split into tasks
  recorded as checkboxes under the item.
- **Parallel work** uses git worktrees, one per package, when packages are independent
  (same layer, no shared files).
- **Reviews**: after implementation, the session asks the relevant reviewers
  (`architect`, `terminology-reviewer`, plus `native-code-reviewer` for C,
  `security-reviewer` for parsers and protocols).
- **GitHub**: issues and PRs can be delegated with `@claude` (workflow `claude.yml`).

## Claude Code in the cloud

Implementation sessions run primarily as Claude Code cloud sessions (claude.ai/code,
`claude --cloud`, mobile app), with the repository's `CLAUDE.md`, `.claude/agents/`,
`.claude/commands/` and `.claude/settings.json` loaded from the clone.

- **Environment**: `hecate`, configured as described in
  [`tools/cloud/README.md`](../../tools/cloud/README.md): custom network allowlist
  (lua.org, luarocks.org, ...), longer command timeouts, setup script installing Lua 5.5
  and LuaRocks 3.13+. Phase 0 replaced the setup script with the pinned bootstrap.
- **Platforms**: cloud VMs are Linux x86_64. macOS and Windows are covered by the CI
  matrix; sessions iterate on pull requests with Auto-fix.
- **Parallelism**: one cloud session per independent roadmap item or package, each on
  its own branch and pull request. A Claude Code project can coordinate several sessions
  for one phase.
- **Local continuation**: `claude --teleport` pulls a cloud session and its branch into a
  local terminal when the owner wants to take over.
- **Safety**: branch protection on `main` (pull request and passing checks required),
  `.claude/settings.json` denies force-pushes, pushes to `main`, tags and publishing;
  the GitHub proxy also refuses tag pushes.
- **GitHub Action**: `claude.yml` (API-key billing) is optional when cloud sessions and
  Auto-fix are used; it runs only when the repository variable
  `CLAUDE_ACTION_ENABLED` is `true`.

## Relay

Usage is limited, so the implementation runs as a **relay** of short, resumable units
rather than one long session. Claude cannot measure the usage it has left; the design
makes every interruption harmless instead.

- **State lives in GitHub**, never in a session: the roadmap on `main`, open pull
  requests labelled `relay`, and a `HANDOFF.md` note on each relay branch (template in
  `.github/relay/`), updated and pushed after every step.
- **Procedure**: `.claude/commands/relay.md` (resume an unfinished relay pull request
  first, otherwise start the next unblocked roadmap item; one item per run; never merge).
- **Phase gates**: the last item of every phase is a verification (completeness, it works,
  coherence, open questions) that produces `docs/reviews/phase-<n>.md`; the relay starts no
  item of the next phase until the gate is ticked (`docs/roadmap.md`, "Phase gates").
- **Locking**: `lock_until` in `HANDOFF.md` prevents two runs from working on the same
  item.
- **Automatic restart**: a Claude Code **routine** (claude.ai/code/routines) using the
  `hecate` environment and the prompt "Follow `.claude/commands/relay.md` exactly."
  - schedule trigger: every 3 hours (custom cron via `/schedule update`; the minimum is
    one hour, and routine runs have a daily cap per account);
  - GitHub trigger: `pull_request.closed`, filter "is merged", so the next item starts
    as soon as the owner merges one.
  When a run hits the usage limit it stops; the pushed state lets the next run, after
  the usage window resets, continue where it stopped. Runs rejected while the limit is
  reached simply do nothing.
- **Owner touchpoints**: reviews and merges of relay pull requests; issues labelled
  `needs-decision`; pausing the routine from its page when needed.

## Human gates

The owner, not agents, decides on: promoting ADRs to `Accepted`, freezing public APIs,
adding third-party dependencies, releases, and anything listed as `decision` in
open-questions.md. Agents prepare the material for these decisions.
