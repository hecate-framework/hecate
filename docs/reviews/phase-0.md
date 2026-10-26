# Phase 0 gate report

Date: 2026-10-25. Verified at `main` ded2660 (merge of pull request 34), on Linux (Lua 5.5.1,
cargo 1.97, GCC 13.3). Windows and macOS results are those of the CI run on that commit.

## 1. Completeness

| Roadmap item | Evidence |
|---|---|
| Spikes OQ-1, OQ-2, OQ-3 | Reports `docs/spikes/OQ-1.md`, `OQ-2.md`, `OQ-3.md`; outcomes recorded in "Resolved" of `docs/open-questions.md`. |
| Spikes OQ-4, OQ-5, OQ-6 | Reports `docs/spikes/OQ-4-tls.md`, `OQ-5-json-codec.md`, `OQ-6-http-parser.md`; owner decisions in ADRs 0021, 0020, 0019. |
| Pinned cloud bootstrap | `tools/cloud/setup.sh`, `tools/cloud/README.md`. |
| Contributor bootstrap | `tools/bootstrap/bootstrap.sh`, `bootstrap.ps1`. |
| Monorepo tooling | Rockspecs per package (`check-rockspecs` ok), `.luarc.json`, harness in `tools/harness`. |
| CI matrix | `.github/workflows/ci.yml`: ubuntu, macos, windows. Last run on `main` (ded2660): success. |
| Task runner and Phase 0 tasks | `lua tools/run.lua --list` lists 32 tasks; every task named by the roadmap item exists in `tools/tasks/`. |
| Git hooks | `tools/hooks/{install,pre-commit,commit-msg}.lua`; tests in `tools/tests`. |
| `ci.yml` calling `tools/` tasks only | Read: it calls `lua tools/run.lua ...` for planning, builds, gates and tests. |
| Repository settings | Labels as code (`.github/labels.yml`, `labels.yml` workflow), `CODEOWNERS`. Branch protection and secrets are GitHub settings: not verifiable from a clone, to be confirmed by the owner. |
| Global-declaration idiom and formatter choice | OQ-3 resolved; `docs/architecture/coding-standards.md`; `format` and `format-check` succeed as documented no-ops. |
| `CLAUDE.md` commands | Each command of the section runs (see section 2). |

No stub, `TODO` or silent deviation was found in `tools/` for the above.

## 2. It works

Run from a fresh clone of the branch, on Linux:

| Command | Result |
|---|---|
| `check-adr-index`, `check-boundaries`, `check-changelog`, `check-glossary`, `check-links`, `check-lua-constructs`, `check-package-structure`, `check-rockspecs`, `check-versions`, `check-docs-examples`, `check-licenses` | ok |
| `lint`, `format-check` | ok |
| `gen-catalogue --check`, `gen-dependency-graph --check`, `gen-llms-txt --check` | ok |
| `build-native json`, `net`, `doc` | ok |
| `fetch-fixtures json`, `doc`, then `test` (all packages and `tools`) | ok, no failing case |
| `typecheck` | not run locally: `lua-language-server` is absent from the cloud image; the task is part of the CI gate list (`ci.yml`) and CI is green. |

`build-native core` and `reactor` report failure on this host because those packages have
no native module of their own (`luv` comes from the system rock); this is not a gap.

Exit criterion "CI is green on all three platforms with a trivial test in every package
skeleton": CI run 309 on `main` succeeded on ubuntu, macos and windows.

## 3. Coherence

Coherence means that every concept is named and identified identically in every file, because
it shapes what users of the libraries read and type. The first pass of this gate only ran the
mechanical checks (links, ADR index, generated catalogue) and was rejected by the owner as not
being coherence. The audit was redone file by file against `docs/glossary.md` and ADR 0004; the
complete findings, with quoted lines, are in
[phase-0-coherence-findings.md](phase-0-coherence-findings.md): 36 findings, 28 user-facing,
about 26 small fixes, 5 medium, and the ones below needing the owner.

Coverage is stated in the findings ("Method and coverage"): the glossary, specifications,
vision, developer-experience, READMEs and tools documents were read in full; ADRs, open
questions, the website (en, fr), the other agents and commands and the Lua sources were covered
by targeted searches; `docs/spikes/`, the Rust and C sources and `.github/` were not covered.
That uncovered part is a known hole of the audit and is to be done by the fix item or the next gate.

Main gaps: "unit of work" and "task" used for coroutines (F01, F03); "ambient context" absent from
the glossary while `log` still says "per-scope context" (F02); "channel" used for the message pipe
(F04); the developer-experience document and `object-model.md` disagree with ADR 0007 and the code
(F06, F07); `reactor` and `net` order the same operations oppositely (`pipe_connect` versus
`connect_pipe` (now verb-first everywhere), F17); error classes without the `Error` suffix in `data-access.md` (F10); README
claims contradicting specifications (F05, F12, F13); stale statements (F20, F24, F26, F28).

Fixed in this pull request, with the owner's decisions, except what the findings' "Resolution" lists as open
(part of F16 as OQ-58, the French glossary page). F07 was decided by the owner (option B) and applied. The gate stays unticked until the
owner has reviewed.

## 4. Open questions

The coherence audit raised decisions for the owner (F07, F12, F17, F19, F34 and parts of F06 and F16);
they were taken, except the one that became OQ-58 (OQ-57 was decided). None of the existing open questions
blocks Phase 1 work.
OQ-3 (formatter) is resolved as "none until a formatter supports Lua 5.5"; recommended to
revisit when StyLua parses `global` and named varargs. Branch protection and secrets
(roadmap item "Repository settings") need the owner's confirmation.

## Verdict

Open: the items listed in the findings' "Resolution". The gate is not ticked.
