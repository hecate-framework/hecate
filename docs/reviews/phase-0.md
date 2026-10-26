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
being coherence. The audit was redone file by file, in three passes, against `docs/glossary.md` and
ADR 0004; the findings, with quoted lines, are in
[phase-0-coherence-findings.md](phase-0-coherence-findings.md): 75 findings (F01 to F75), all fixed in this
pull request with the owner's decisions (verb-first transport names, qualified error prefixes,
`request.parameters`, `core.class`, `severity`, `duplicate_member_name`, and the data-access layering of
[ADR 0026](../adr/0026-query-sql-layering.md)).

Coverage: the three passes read every tracked file in full (glossary, specifications, ADRs, open questions,
spikes, READMEs, agents, commands, tools, `.github`, website in English and French, Lua, Rust and C sources,
tests, examples, benchmarks), except vendored `yyjson`, binary files, `Cargo.lock` files and generated data.
Sample pages, fixtures and generated tables had their headers and vocabulary checked.

## 4. Open questions

The coherence audit raised decisions for the owner (F07, F12, F17, F19, F34 and parts of F06 and F16);
they were all taken (F07, OQ-57, OQ-58, OQ-60, OQ-61). None of the existing open questions
blocks Phase 1 work. OQ-62 (new): specification sections for `container`, `config` and `log`.
OQ-3 (formatter) is resolved as "none until a formatter supports Lua 5.5"; recommended to
revisit when StyLua parses `global` and named varargs. Branch protection and secrets
(roadmap item "Repository settings") need the owner's confirmation.

## Verdict

No open gap and no open question. The remaining small items listed in the findings' "Resolution" are recorded
deferrals. The gate is ticked.
