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
- [ ] Workflow `ci.yml` (affected packages × three platforms) calling only `tools/` tasks.
- [ ] Repository settings: branch protection, labels, secrets (automation.md §3).
- [ ] Settle the global-declaration idiom and formatter choice; update
      coding-standards.md (OQ-3).
- [ ] Fill the "Commands" section of `CLAUDE.md`.

Exit: CI is green on all three platforms with a trivial test in every package skeleton.

## Phase 1 — Core and runtime

- [ ] `core`: object model (classes, traits, interfaces, conformance), error hierarchy,
      enumerations, compatibility shims ([object-model.md](architecture/object-model.md)).
- [ ] `reactor`: reactor over luv, scheduler, futures, `fork`/`join`/`select`,
      deadlines, scopes and cancellation, channels, semaphores, mutexes, monitors,
      timers, thread-pool offloading, signals ([concurrency.md](architecture/concurrency.md)).
- [ ] `net`: TCP/UDP streams, DNS, buffered readers/writers, TLS (after OQ-4).
- [ ] `json`: codec (after OQ-5).
- [ ] `log`: structured logging, RFC 5424 severities, per-scope context.
- [ ] Benchmarks harness and first scenario (TCP echo); `benchmarks.yml`.
- [ ] Workflows `native.yml`, `security.yml`, `nightly.yml`; tasks `sanitize`, `fuzz`,
      `leaks`, `coverage`, `bench`, `check-licenses`.

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

- [ ] Spike OQ-11 (documentation tooling: site generator and code-reference renderer),
      report with rendered samples submitted to the owner before the website skeleton.

## Phase 3 — Contracts and tooling → `0.1.0`

- [ ] `openapi`: OpenAPI 3.1 assembly, served endpoint, export, contract diff.
- [ ] `test`: test framework, runner, in-process client, fixtures, contract conformance,
      reporters (TAP, JUnit XML), coverage.
- [ ] `doc`: project documentation generator (code reference + API reference).
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
- [ ] Release automation: `release.yml`, `docker.yml`, `cli-e2e.yml`, `website.yml`
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

## Continuous

- Website: French translation kept in sync; further locales by contribution.
- Benchmarks published per release.
