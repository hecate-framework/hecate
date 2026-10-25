# Automation: CI/CD and repository scripts

Status: specification; [ADR 0015](../adr/0015-ci-cd-on-github-actions.md) (Accepted).

Principle: **workflows are thin, scripts are thick.** Every CI check is a script in
`tools/` that runs identically on a developer machine, in CI and for agents. Workflows
only prepare runners, call scripts and publish results.

Until the CLI exists, tasks run with `lua tools/run.lua <task> [args]` (after
`tools/bootstrap`). Afterwards `hecate task <task>` is an alias. Every task supports
`--json` output and returns a non-zero exit code on failure.

## 1. Script catalogue (`tools/`)

Status column: `done` = implemented in `tools/`, `now` = workflow exists today, `P0` = to write in Phase 0, `P1+` = later.

### Bootstrap

| Script | Purpose | Status |
|---|---|---|
| `tools/bootstrap/bootstrap.sh` | Linux/macOS: download, verify (SHA-256) and build Lua 5.5 + LuaRocks into `.hecate/toolchain/`; install dev rocks | P0 |
| `tools/bootstrap/bootstrap.ps1` | Windows equivalent (MSVC) | P0 |
| `tools/run.lua` | task runner: discovers tasks in `tools/tasks/*.lua`, `run.lua --list` documents them | P0 |
| `tools/hooks/install.lua` | installs git hooks (pre-commit: format-check + lint on staged files; commit-msg: Conventional Commits) | P0 |

### Quality gates

| Task | Checks | Status |
|---|---|---|
| `format` / `format-check` | formatter on Lua sources (and `clang-format` on C) | done |
| `lint` | linter rules from coding-standards.md | done |
| `typecheck` | `lua-language-server --check` with the repository `.luarc.json`, zero diagnostics | done |
| `fetch-fixtures` | downloads the third-party test data a package declares in `tests/external.lua` into `.hecate/fixtures/` (git-ignored) with git at a pinned commit (`HECATE_FIXTURES_LATEST=1`: the head of the default branch, for scheduled runs); suites that need it skip locally without it and fail in CI | done |
| `check-lua-constructs` | only the 5.5 constructs allowed by ADR 0001 | done |
| `check-boundaries` | layer rules (overview.md): requires match declared rockspec dependencies, no upward or cyclic dependency, `luv` only in `reactor`, raw `setmetatable` only in `core` or justified | done |
| `check-glossary` | deny-list of discouraged identifiers in `packages/**/src` (from glossary "Instead of" columns) | done |
| `check-annotations` | every exported symbol has LuaLS annotations; functions that suspend carry `---@async`; functions returning `nil` for absence declare a nullable return (ADR 0018) | P1 |
| `check-versions` | all rockspecs and `VERSION` agree (ADR 0005); `lua >= 5.5, < 5.6` everywhere | done |
| `check-rockspecs` | rockspec lint (`luarocks lint`), fields, licenses, sources | done |
| `check-package-structure` | every `packages/<name>` has README.md, CLAUDE.md, rockspec, `tests/`, and an agent in `.claude/agents/pkg-<name>.md` | done |
| `check-adr-index` | `docs/adr/README.md` lists every ADR with its actual status | done |
| `check-changelog` | pull requests touching `packages/` add an `[Unreleased]` entry | done |
| `check-docs-examples` | every code block of the website introduced by `<!-- example: <path> -->` is identical to that file and the file exists (the examples run in the tests of their package) | done |
| `check-translations` | missing/stale translations (front matter `source_revision`) | P3 |
| `check-links` | internal Markdown links and anchors | done |
| `check-licenses` | third-party code and rocks have compatible licenses; `THIRD_PARTY_NOTICES` up to date | P1 |

### Tests and measurements

| Task | Purpose | Status |
|---|---|---|
| `test [packages] [--integration] [--tag t]` | run tests (bootstrap harness, then `hecate.test`); a test that runs longer than `HECATE_TEST_TIMEOUT` seconds (default 120) fails its file and is named; with `CI=true` each file is announced on standard error; the CI job has a 30-minute limit | done |
| `coverage` | LCOV report, per-package thresholds (core/reactor/router/schema ≥ 90 %) | P1 |
| `affected [--base ref]` | packages affected by a diff, following reverse dependencies; used to shrink CI | done |
| `needs <package> [packages...]` | `true` when a listed package is, or depends on, `<package>`; CI builds the native modules of `json` when it says so (OQ-53: no fallback backend) | done |
| `matrix` | emits the CI matrix (platforms × packages × services) as JSON | done |
| `services up\|down\|status` | start database servers locally via `tools/services/compose.yaml` (same versions as CI) | P4 |
| `bench [scenario] [--compare ref]` | run benchmarks, compare with a baseline, fail above threshold | P1 (partly done: `bench [name...] [--list] [--runs=N] [--pin=CPUS] [--out=DIR]` browses and runs the `packages/*/benchmarks/*.lua` files on a Linux host, with host reports and a summary of the runs; `bench <scenario> [--compare=ref]` runs a network scenario of `benchmarks/scenarios/` and its interleaved A/B comparison against a git reference, Mann-Whitney U with p < 0.01 and a 10 % threshold; the `plaintext`, `json` and later scenarios come with their packages) |
| `fuzz <target> [--seconds n]` | libFuzzer targets for C parsers and codecs | P1 |
| `sanitize` | build native modules with ASan/UBSan and run their tests | P1 |
| `leaks` | run reactor-heavy suites with coroutine/handle leak detection | P1 |
| `cli-e2e` | generate each CLI template, install, test, serve, request | P3 |

### Generators

| Task | Output | Status |
|---|---|---|
| `new-package <name> --layer L` | package skeleton + CLAUDE.md + agent + catalogue entry | done |
| `gen-catalogue` | `packages/README.md` table from rockspecs and READMEs | done |
| `gen-dependency-graph` | Mermaid graph in overview.md (between markers) | done |
| `gen-reference` | Markdown reference from LuaLS JSON export into `website/en/reference/<package>/` (not committed, git-ignored; skipped with a message without `lua-language-server`, `--require` fails instead; `build.lua --reference` runs the same generator before a site build; OQ-40) | done for `core`, `reactor`, `net` |
| `gen-llms-txt` | `llms.txt` and `website/public/llms.txt`, `llms-full.txt` | done (root `llms.txt` package list; website copies in P3) |
| `gen-error-codes` | error code reference page from error classes | P2 |
| `gen-config-reference` | configuration keys reference from config schemas | P2 |
| `gen-meta` | LuaLS `---@meta` files from schemas (also exposed to users via the CLI) | P2 |

### Release

| Task | Purpose | Status |
|---|---|---|
| `release prepare <version>` | bump `VERSION`, rockspecs, changelog section (with Lua line), compatibility matrix; open a release PR | P3 |
| `release verify` | all gates green, changelog complete, docs built, no `Proposed` ADR blocking | P3 |
| `release rocks` | build and publish every rock in dependency order (idempotent, resumable) | P3 |
| `release binaries` | build CLI executables for 6 targets | P3 |
| `release sbom` / `release sign` | SPDX SBOM, cosign signatures, checksums | P3 |
| `release packages` | Homebrew formula (`homebrew-hecate`), winget and Scoop (`scoop-hecate`) manifests | P3 |
| `split [--package p] [--ref r] [--push]` | split `packages/<name>` into `hecate-framework/hecate-<name>` with deterministic history, inject `.github/mirror-template/`, push branch or tag (ADR 0017, tool choice OQ-17) | P3 |
| `mirrors ensure` | create missing mirror repositories and apply settings (issues/wiki off, description, topics, homepage) through the GitHub API | P3 |
| `check-mirrors` | verify mirror `main` and tags equal the split of the monorepo, and settings are correct | P3 |

## 2. Workflows (`.github/workflows/`)

| Workflow | Trigger | Jobs | Status |
|---|---|---|---|
| `docs.yml` | PR, push to main (Markdown changes) | markdownlint, link check | now |
| `pr-hygiene.yml` | PR opened/edited | Conventional Commits title, path labels | now |
| `claude.yml` | `@claude` in issues, PR comments and reviews | Claude Code GitHub Action | now (needs `ANTHROPIC_API_KEY` secret) |
| `ci.yml` | PR, push to main | `affected` → matrix {ubuntu, macos, windows} × affected packages: bootstrap (cached), format-check, lint, typecheck, check-*, unit tests, coverage upload | P0 |
| `native.yml` | PR touching `csrc/`, nightly | GCC/Clang/MSVC builds, sanitizers, short fuzzing (PR), long fuzzing (nightly) | P1 |
| `integration.yml` | PR touching data/net packages, nightly | service containers: PostgreSQL, MySQL, MariaDB, Redis, Valkey, later MongoDB, SQL Server — two most recent major versions each | P4 |
| `benchmarks.yml` | push to main, PR labelled `performance` | GitHub-hosted runner, `bench --compare main` with interleaved A/B runs on the same runner (relative comparison only, OQ-14), repeated runs (7 rounds each side for `tcp-echo`, at least 5 are required; the table asks for more as scenarios stabilise), the **median** is the reference value (mean, min and max reported alongside, since shared runners are noisy), deltas and significance in the job summary (a PR comment and the published history come later), history published as indicative | P1 (delivered for `tcp-echo`: `benchmarks.yml`) |
| `website.yml` | PR (build only), push to main (deploy) | gen-reference, site build (`hecate doc`, or the interim generator chosen after OQ-11), link check, translation status, deploy to GitHub Pages | P2; first version done (pinned LuaLS, `build.lua --reference --strict`, base path and origin from `configure-pages`, deploy from main; link check inside `--strict`; translation status and `hecate doc` pending; needs Settings > Pages > Source = GitHub Actions) |
| `docker.yml` | changes in `docker/`, weekly, release | multi-arch builds (buildx), Trivy scan, push on release | P3 |
| `cli-e2e.yml` | PR touching `cli`, nightly | `cli-e2e` on 3 platforms with the built executable | P3 |
| `security.yml` | PR touching a Cargo manifest or lockfile, push to main, weekly | `cargo audit` (known vulnerabilities) and `cargo deny` (licences, bans, sources; policy in `deny.toml`) for the Rust crates, with the tools built from source at pinned versions (done); CodeQL (C), dependency review, OpenSSF Scorecard (to come) | P1 |
| `split.yml` | push to `main`, tag `v*.*.*` | `affected` → `split --push` for affected packages on `main`; all packages on tags (same tag in every mirror) | P3 |
| `labels.yml` | push to `main` touching `.github/labels.yml` | synchronise repository labels from `.github/labels.yml` | now |
| `release.yml` | tag `v*.*.*` (jobs that publish run in environment `release`) | `release verify` → wait for `split.yml` tags → rocks (sources from mirrors) → binaries (6 targets) → sign + SBOM → GitHub Release → Docker → Homebrew tap, Scoop bucket, winget → versioned website | P3 |
| `nightly.yml` | schedule | full matrix including all integration services, long fuzzing, leak detection, dependency freshness report as an issue; `check-mirrors` from P3 | P1 |

Rules:

- Caches: toolchain (`.hecate/toolchain`) keyed by bootstrap script hash and OS;
  LuaRocks tree keyed by rockspecs.
- Required checks on `main`: `ci`, `docs`, `pr-hygiene`, and from their phase on,
  `native`, `integration`, `website`.
- Third-party actions pinned by commit SHA in every workflow, with the tag as a trailing comment
  (`uses: owner/name@<sha> # v1`); Dependabot updates both. (Owner, 2026-10-18; done.)
- Licences: the Rust crates must be permissive (`deny.toml`), so that Hecate stays MIT; any other
  licence fails CI and the project owner decides. Dependabot also watches the Rust crates of the
  native modules (`.github/dependabot.yml`).
- Every workflow uploads machine-readable reports (JUnit XML, LCOV, SARIF, benchmark
  JSON) as artefacts.

## 3. Repository settings (to configure on GitHub)

- Branch protection on `main`: required checks, linear history, signed commits optional.
- Labels: defined in `.github/labels.yml` and synchronised by `labels.yml`; never edited
  in the GitHub UI.
- Release secrets live in a GitHub **environment** `release` on the `hecate` repository,
  with the owner as required reviewer, so publishing waits for an explicit approval:
  `LUAROCKS_API_KEY` (account `hecate-framework`), and later `DOCKERHUB_TOKEN` and
  signing keys. Not organisation secrets: only this repository publishes.
- Other secrets: `ANTHROPIC_API_KEY` only if `claude.yml` is enabled, `DOCKERHUB_TOKEN`,
  signing keys, and a GitHub App (preferred over deploy keys) with write access to the
  mirrors, the tap and the bucket: `MIRROR_APP_ID`, `MIRROR_APP_PRIVATE_KEY` (Phase 3).
- Mirrors (`hecate-framework/hecate-<name>`): created by `mirrors ensure`, never configured by hand.
- GitHub Pages for the website; Discussions for questions.
