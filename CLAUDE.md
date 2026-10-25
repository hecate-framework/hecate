# CLAUDE.md — working on Hecate

Hecate is a modular, contract-first web API framework for **Lua 5.5**, with its own
asynchronous runtime (libuv via luv), HTTP stack, schemas, OpenAPI generation, test
framework, documentation generator, database drivers, ORM and CLI.

The project is in **early implementation**: the design is complete, and the foundations are
written (`core`, `reactor`, `net`, `json`, `log`, `doc`; Phase 0 and most of Phase 1 of the
roadmap). The other packages are still specifications. Your job is to implement the rest,
milestone by milestone, following the roadmap.

## Sources of truth, in order of precedence

1. `docs/adr/` — Architecture Decision Records. `Accepted` ADRs are binding.
   `Proposed` ADRs are the working hypothesis: implement them as written, and record
   any problem you find in `docs/open-questions.md` instead of silently deviating.
2. `docs/architecture/` — specifications per area.
3. `packages/<name>/README.md` — scope and responsibilities of each package.
4. `docs/roadmap.md` — what to build next and the exit criteria of each phase.
5. `docs/developer-experience.md` — the target user experience. Code snippets there
   are illustrative; when they conflict with an ADR or a specification, those win.

If something is not decided anywhere, **do not invent it silently**. Either write a
new ADR with status `Proposed` (use `/new-adr`) or add an entry to
`docs/open-questions.md`, then proceed with the most conservative option.

## Non-negotiable rules

- **Lua 5.5 only.** Use 5.5 features freely, but only the 5.5-only constructs listed
  in ADR 0001 as having a mechanical lowering to 5.4. Nothing else that would block
  a future 5.4 build.
- **No implicit globals.** Library code declares no globals at all.
- **English everywhere in the repository**: code, comments, annotations, error
  messages, commit messages, engineering docs. The public website is translated
  separately (`website/`).
- **Academic vocabulary.** Follow `docs/glossary.md`. Standards (RFCs, JSON Schema,
  OpenAPI, SQL) keep their own terms. Do not introduce names borrowed from other
  ecosystems when the glossary defines a term.
- **Monorepo only** (ADR 0017). All work happens here. `hecate-framework/hecate-<name>`
  repositories are generated read-only mirrors: never edit, push to or open pull
  requests against them.
- **One framework.** Reuse the shared object model (`hecate.core`), error hierarchy,
  logging and configuration. Never introduce a parallel mechanism inside a package.
- **Layering.** A package may depend only on packages of a lower layer
  (`docs/architecture/overview.md`). No dependency cycles.
- **Cross-platform.** Linux, macOS and Windows. Anything platform-specific is isolated
  and tested on all three in CI.
- **No new third-party dependency** (Lua rock or C library) without an ADR.
- **Every public API** carries LuaLS annotations (`---@class`, `---@param`,
  `---@return`, ...). They feed the generated reference documentation.

## Definition of done for any task

- Implementation follows the relevant specification and ADRs.
- Unit tests, and integration tests where I/O is involved, pass on the CI matrix.
- Public API annotated; reference docs updated in `website/` (English source).
- Package README updated (status, API summary).
- `CHANGELOG.md` updated under `[Unreleased]`.
- Benchmarks updated when the change touches a hot path (`benchmarks/`).
- Commit messages follow Conventional Commits, scoped by package:
  `feat(router): ...`, `fix(postgresql): ...`.

## Workflow

1. Pick the next unchecked item in `docs/roadmap.md` (or the one you are given).
2. Read its specification, the package README and the ADRs they reference.
3. If the item needs a decision that is missing, record it first (ADR or open question).
4. Write tests first for public behaviour, then implement.
5. Run formatter, linter, type checker and tests (commands below once tooling exists).
6. Update docs and changelog, then tick the roadmap item.

## Agents and commands

- **Specialists**: one subagent per package, `.claude/agents/pkg-<name>.md`. Delegate
  package work to it; it knows the package's scope, standards and invariants.
- **Reviewers**: `architect`, `terminology-reviewer`, `api-reviewer`, `dx-reviewer`,
  `test-engineer`, `performance-engineer`, `security-reviewer`,
  `native-code-reviewer`, `cross-platform-reviewer`.
- **Production**: `docs-writer`, `translator-fr`, `ci-engineer`, `release-manager`.
- **Commands**: `/implement-task`, `/new-adr`, `/new-package`, `/review-package`,
  `/spike`, `/check`, `/write-docs`, `/translate`, `/bench`, `/prepare-release`.
- After implementing anything non-trivial, run `/review-package` (or the relevant
  reviewers) before reporting completion.
- Details: `docs/architecture/ai-assisted-development.md`.

## Human gates

Only the project owner: promotes ADRs to `Accepted`, adds third-party dependencies,
freezes public APIs, tags releases, publishes rocks and images, resolves `decision`
entries in `docs/open-questions.md`, and merges pull requests into `main`.

Git workflow: work on a branch, push it, open a pull request, follow its CI on the three
platforms. Never push to `main`, never force-push, never create tags, never publish.

**Resuming an unmerged pull request: push to that pull request's own branch.** Check out its
head branch and push there, even when the session designates another branch. Never carry the
work over to a session branch: parallel branches for one subject mean the same work is redone
and has to be merged by hand. Open a new branch only for a subject that has no open pull request.

## Cloud sessions

Most sessions run in Claude Code cloud sessions (Ubuntu 24.04 x86_64, environment
described in `tools/cloud/README.md`). macOS and Windows behaviour is verified only
through GitHub Actions: push, open the pull request, and fix CI failures on the three
platforms before reporting completion. If a download is blocked by the network
allowlist, say which domain is needed instead of working around it.

## Relay (autonomous runs)

When started by the relay routine, or asked to "continue the relay", follow
`.claude/commands/relay.md`: resumable steps, `HANDOFF.md` updated and pushed after each
step, one roadmap item per run, never merge.

## Commands

Tooling does not exist yet; it is built in Phase 0 as Lua tasks run by
`lua tools/run.lua <task>` (catalogue: `docs/architecture/automation.md`). Fill this
section as soon as each command is available:

Run `lua tools/run.lua --list` for the full catalogue.

- Format: none (the repository has no formatter until one supports Lua 5.5, OQ-3);
  `lua tools/run.lua format-check` succeeds as a no-op.
- Lint: `lua tools/run.lua lint`
- Type check (LuaLS): `lua tools/run.lua typecheck` (needs `lua-language-server`)
- Other gates: `check-lua-constructs`, `check-boundaries`, `check-glossary`,
  `check-versions`, `check-rockspecs`, `check-package-structure`, `check-adr-index`,
  `check-changelog`, `check-links`, `check-docs-examples`, `check-licenses`
- Native modules: `build-native <package>` (needs `cargo` or a C compiler), `sanitize [package]`
  (ASan/UBSan, Linux), `fuzz <target> [--seconds n]` or `fuzz --list` (cargo-fuzz, nightly Rust)
- Robustness and measurement: `leaks [package]`, `coverage [package]`, `fetch-fixtures <package>`,
  `needs <package>`
- Test all packages: `lua tools/run.lua test`
- Test one package: `lua tools/run.lua test <package>` (tools: `test tools`)
- Affected packages: `lua tools/run.lua affected --base origin/main`
- Benchmarks: `lua tools/run.lua bench --list`; `bench <scenario> [--compare=ref]` (Linux and macOS)

## Repository map

- `docs/vision.md` — goals, non-goals, principles.
- `docs/developer-experience.md` — target experience for users.
- `docs/glossary.md` — mandatory vocabulary.
- `docs/architecture/*.md` — specifications.
- `docs/adr/*.md` — decisions.
- `docs/roadmap.md`, `docs/open-questions.md`.
- `packages/<name>/` — one rock per directory (`hecate-<name>`, module `hecate.<name>`).
- `website/` — public documentation site. `docker/` — images. `benchmarks/`, `examples/`.
