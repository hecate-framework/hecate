# Roadmap

Phases are sequential; items inside a phase can proceed in parallel when their
dependencies allow. Each phase ends with explicit exit criteria. Tick items as they land.

Versions: Phases 0–2 produce no release. Phase 3 ends with `0.1.0` (alpha), Phase 4 with
`0.2.0`. All packages share one version ([ADR 0005](adr/0005-single-brand-monorepo-lockstep-versioning.md)).

## Phase 0 — Groundwork

Goal: a repository where code can be written, checked and tested on three platforms.

Sessions run in Claude Code cloud sessions (Linux). The first deliverable is therefore a
minimal `ci.yml` matrix (ubuntu, macos, windows) so that spikes and scripts can be
verified on macOS and Windows through pull requests.

- [x] Spike: confirm luv builds and passes its tests against Lua 5.5 on Linux, macOS,
      Windows (resolves OQ-1).
- [x] Spike: confirm LuaRocks 3.x supports Lua 5.5 with project-local trees and
      lockfiles; document the exact commands (OQ-2).
- [x] Spike: assess LuaLS and StyLua support for Lua 5.5 syntax (`global`, named
      varargs) (OQ-3).
- [x] Spikes OQ-4 (TLS: OpenSSL 3, mbedTLS, luaossl, lua-openssl), OQ-5 (JSON: yyjson
      binding, lua-cjson, own codec) and OQ-6 (HTTP/1.1 parser: llhttp, Lua parser):
      build on Lua 5.5 on three platforms, benchmarks, licences, maintenance. Each
      report ends with a recommendation **submitted to the owner**; no implementation
      depending on them starts before the owner decides.
- [x] Replace `tools/cloud/setup.sh` with the pinned bootstrap; update the cloud
      environment accordingly.
- [x] Contributor bootstrap: a script that builds Lua 5.5 + LuaRocks into
      `.hecate/toolchain/` for working on this repository (temporary until the CLI
      exists).
- [x] Monorepo tooling: per-package rockspecs, a root task runner, formatter, linter,
      LuaLS configuration (`.luarc.json`), test runner bootstrap (temporary harness
      until `hecate.test` exists, see ADR 0008).
- [x] CI: GitHub Actions matrix `{ubuntu, macos, windows} × Lua 5.5`, C toolchains
      (sanitizers on Linux move to the Phase 1 `native.yml` item: no native code yet).
- [x] `tools/run.lua` task runner and the Phase 0 tasks of the catalogue in
      [automation.md](architecture/automation.md) (format, lint, typecheck,
      check-lua-constructs, check-boundaries, check-glossary, check-versions,
      check-rockspecs, check-package-structure, check-adr-index, check-changelog,
      check-links, test, affected, matrix, new-package, gen-catalogue,
      gen-dependency-graph, gen-llms-txt).
- [x] Git hooks (`tools/hooks`).
- [x] Workflow `ci.yml` (affected packages × three platforms) calling only `tools/` tasks.
- [x] Repository settings: branch protection, labels, secrets (automation.md §3).
- [x] Settle the global-declaration idiom and formatter choice; update
      coding-standards.md (OQ-3).
- [x] Fill the "Commands" section of `CLAUDE.md`.

Exit: CI is green on all three platforms with a trivial test in every package skeleton.

## Phase 1 — Core and runtime

- [x] `core`: object model (classes, traits, interfaces, conformance), error hierarchy,
      enumerations, compatibility shims ([object-model.md](architecture/object-model.md)).
- [x] `reactor`: reactor over luv, scheduler, futures, `fork`/`join`/`select`,
      deadlines, scopes and cancellation, channels, semaphores, mutexes, monitors,
      timers, signals ([concurrency.md](architecture/concurrency.md)).
- [x] Website skeleton in `website/en` with the Hecate visual identity (`brand/` of the
      organisation `.github` repository): layout, navigation, theme, reference pages for
      `core`, `reactor` and `net`. Owner priority: docs ship before the first usable
      framework version. Delivered: the site builds from `hecate.doc` (generated reference,
      strict link check), `website.yml` builds it on pull requests and deploys it to GitHub
      Pages from `main` (Settings > Pages > Source = GitHub Actions), hand-written how-to
      guides and explanations for `net` and the `reactor` primitives, the public glossary,
      the French translation of those pages (13 pages; terminology in
      `website/fr/glossary-terms.md`), and `check-docs-examples` (code blocks equal their
      tested example files). Still to come, in their own items: tutorials and the other
      packages' guides as the packages land, the translation status check, `hecate doc` for
      user projects, and the `doc` item below.
- [x] `net`: TCP/UDP streams, DNS, buffered readers/writers, TLS (after OQ-4). Benchmarks of its hot paths wait for the harness item below.
- [x] `json`: codec (after OQ-5). Lua API, pure-Lua backend, yyjson decoder (C), `serde_json` encoder (Rust, OQ-52), corpus and fuzz tests, `bench json`, examples and how-to; native modules built and tested on Linux, macOS and Windows in CI. The native modules in the rockspec and the binary rocks come with release automation (Phase 3). The network benchmark scenarios wait for the harness item below; the micro-benchmark `packages/json/benchmarks/codec.lua` runs with `lua tools/run.lua bench json` and its numbers are measured and published by the owner on dedicated hardware (benchmarks/README.md). Hostile-input costs are open in OQ-54.
- [ ] `json` follow-up: remove the pure-Lua backend once it has no use (OQ-53): encode failures produced by the native module (decode failures already are, OQ-54), `-0` handled natively, the oracle replaced by fixtures, native modules required at run time everywhere (Windows build and binary rocks first).
- [ ] `doc` (minimal) and the reference generator, **pulled forward from Phase 3** (owner
      decision of 2026-10-13, ADR 0012, Accepted, OQ-11): site build from Markdown and the LuaLS export (`---@class` on every module
      table, `---@param name type description`), generated reference pages for `core` and
      `reactor`, the website built by it in CI. Depends on `json` (the export) and on
      `reactor` (file system, OQ-33), both accepted as dependencies of `doc`; the
      third-party dependencies of ADR 0022 (Accepted) are integrated first.
      Replaces the "website skeleton" item above as the way the site is built; OpenAPI
      reference, versioned documentation, runnable examples and `hecate doc build` for user
      projects stay in Phase 3.
- [ ] `doc` theme, mobile navigation (owner report, 2026-10-20): the sidebar menu that browses
      the guides, the reference and the other sections cannot be scrolled on mobile devices.
      Fix it in the theme (a long menu scrolls inside its own container, the page behind it
      does not), and add a check on a narrow viewport (a browser test or a documented manual
      check in `docs/architecture/documentation.md`) so that it is not forgotten again.
- [ ] `log`: structured logging, RFC 5424 severities, per-scope context.
- [ ] Benchmarks harness and first scenario (TCP echo); `benchmarks.yml`.
- [ ] Pin every third-party action of the existing workflows by commit SHA (owner request,
      2026-10-18; [automation.md](architecture/automation.md)); Dependabot keeps them current.
- [ ] Workflows `native.yml`, `security.yml`, `nightly.yml`; tasks `sanitize`, `fuzz`,
      `leaks`, `coverage`, `bench`, `check-licenses`. The native code of `json` (`csrc/native.c`, `native/`) needs its ASan and UBSan build and its libFuzzer targets there (coding-standards.md; today a differential fuzz test in Lua only, native review of the `json` pull request). (`security.yml` has its Rust dependency
      checks, `cargo audit` and `cargo deny`; CodeQL, dependency review and Scorecard remain.)

Exit: an echo server handles 10 000 concurrent connections on each platform; structured
concurrency test suite passes; benchmark baseline recorded.

## Phase 2 — HTTP and framework kernel

- [ ] `http`: HTTP/1.1 server (llhttp, OQ-6) and client, message model, streaming,
      keep-alive, limits.
- [ ] `router`: radix tree, URI template subset, 404/405, reverse routing.
- [ ] `schema`: refinement types, composition, coercion, validation with JSON Pointer
      error paths, JSON Schema 2020-12 emission.
- [ ] `container`: IoC container, lifetimes, cycle detection at boot.
- [ ] `config`: layered configuration validated by schemas.
- [ ] `kernel`: application, modules, controllers, route modules, filters, problem
      details, lifecycle, multi-process workers, graceful shutdown.
- [ ] Example: `examples/hello` (JSON API with validation).
- [ ] Benchmarks: plaintext and JSON scenarios.

Exit: `examples/hello` runs on three platforms with N workers; invalid input yields
RFC 9457 problem details; graceful shutdown drains in-flight requests.

## Phase 2 — additional spike

- [ ] `reactor` follow-up: specify then implement `offload` (Lua functions on the libuv
      thread pool), split from the Phase 1 item (OQ-27).
- [x] `reactor`: the multi-process primitives of [ADR 0023](adr/0023-multi-process-serving.md)
      (`spawn`, `ipc` with handle passing, TCP `reuseport`, OQ-8, OQ-43); needed by `kernel`
      for multi-process workers. Spike OQ-8 delivered. `reuseport` needs luv with TCP
      `reuseport` (OQ-43): `reactor.supports_reuseport()` reports it and `auto` stays `round_robin`
      until then.

- [ ] Spike OQ-11 (documentation tooling: site generator and code-reference renderer),
      report with rendered samples submitted to the owner before the website skeleton.

## Phase 3 — Contracts and tooling → `0.1.0`

- [ ] `openapi`: OpenAPI 3.1 assembly, served endpoint, export, contract diff.
- [ ] `test`: test framework, runner, in-process client, fixtures, contract conformance,
      reporters (TAP, JUnit XML), coverage.
- [ ] `doc`: project documentation generator for user projects (OpenAPI reference,
      `hecate doc build`); the minimal generator and the code reference moved to Phase 1.
- [ ] `cli` v1: self-contained executable, `new`, `install`, `add`, `remove`, `update`,
      `serve [--watch]`, `test`, `doc`, `contract`, `toolchain`, `doctor`, `version`.
- [ ] Docker images (runtime and build variants, amd64 + arm64).
- [ ] Website: Diátaxis structure, English source, French locale enabled, MDN-like
      theme, getting-started tutorial, reference generated from annotations, built by
      `hecate doc` (ADR 0012, after OQ-11). Pages may be drafted as Markdown earlier.
- [ ] Meta-rock `hecate` (standard edition).
- [ ] Read-only mirrors (ADR 0017): `split`, `mirrors ensure`, `check-mirrors`,
      `split.yml`; Homebrew tap and Scoop bucket repositories (resolves OQ-17).
- [ ] Publish all rocks to luarocks.org (sources from mirrors).
- [ ] `hecate generate workflow` (ci, contract, docs-pages, release) and its templates;
      regenerate the monorepo's `website.yml` with it.
- [ ] Release automation: `release.yml` (including one LuaRocks binary rock per platform for
      the native modules of `net` and `json`, ADR 0021), `docker.yml`, `cli-e2e.yml`, `website.yml`
      and the `release *` tasks.

Exit: from a clean machine on each platform, `install → hecate new → hecate serve`
in under five minutes; tutorial reproducible verbatim.

## Phase 4 — Data access → `0.2.0`

- [ ] Spike OQ-18 (Data Mapper versus Active Record prototypes), report submitted to the
      owner before any `orm` work.
- [ ] `sql`: driver interfaces, connection pool, transactions and savepoints, type
      mapping, instrumentation.
- [ ] `query`: relational-algebra query builder, dialects.
- [ ] `postgresql`: protocol v3, SCRAM-SHA-256, TLS, prepared statements, COPY,
      LISTEN/NOTIFY.
- [ ] `sqlite`: C binding executed on the libuv thread pool.
- [ ] `mysql`: MySQL and MariaDB protocol, `caching_sha2_password`, TLS.
- [ ] `redis`: RESP3, pipelining, publish/subscribe, transactions.
- [ ] `migration`: versioned, reversible migrations, CLI integration.
- [ ] `orm`: data mapper, unit of work, identity map, associations, repositories.
- [ ] Example: `examples/crud` (PostgreSQL), integration tests against every driver in CI
      (service containers).
- [ ] Benchmarks: database scenarios (single query, multiple queries, updates), compared
      with reference clients of other ecosystems (ADR 0014 performance condition).

Exit: `examples/crud` works unchanged on PostgreSQL, MySQL, MariaDB and SQLite.

## Phase 5 — Ecosystem expansion

- [ ] `security`: authentication (bearer tokens, JWT, sessions), authorisation
      policies, password hashing.
- [ ] `mongodb`: OP_MSG protocol, BSON, document mapper.
- [ ] `sqlserver`: TDS protocol.
- [ ] `template`: compiled templates with contextual auto-escaping.
- [ ] `websocket` (RFC 6455).
- [ ] HTTP/2.
- [ ] Further NoSQL drivers by demand (e.g. Cassandra/ScyllaDB CQL).

## Phase 6 — Lua 5.4 support

- [ ] Source lowering tool 5.5 → 5.4 ([ADR 0001](adr/0001-lua-5.5-as-sole-target.md)).
- [ ] CI matrix extended to 5.4; publication strategy for 5.4 artefacts (OQ-7).

## Phase 7 — Code review and quality pass

- [ ] Review all code, including `tools/`, for readability and quality: naming, function and
      module size, duplication, dead code, comment accuracy, consistency with
      [coding-standards.md](architecture/coding-standards.md) and the glossary.
- [ ] Use the SonarLint / SonarSource rule set as the quality reference (cognitive
      complexity, duplicated blocks, dead code, unused variables and parameters, empty
      or commented-out code, overly long functions and parameter lists). Adopting any
      Sonar tool or Lua analyser in CI is a new dependency and needs an ADR first;
      until then, apply the rules by review and, where cheap, as `lint` task rules.
- [ ] Simplify without changing behaviour: refactors are covered by the existing tests,
      and benchmarks confirm no hot-path regression.
- [ ] Re-run all reviewer agents (`/review-package`) on every package and record the
      findings fixed or deferred.

Exit: every package reviewed, findings resolved or tracked in `docs/open-questions.md`,
CI green on the three platforms.

## Continuous

- Website: French translation kept in sync; further locales by contribution.
- Benchmarks published per release.
