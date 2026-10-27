# Roadmap

Phases are sequential; items inside a phase can proceed in parallel when their
dependencies allow. Each phase ends with explicit exit criteria. Tick items as they land.

Versions: Phases 0–2 produce no release. Phase 3 ends with `0.1.0` (alpha), Phase 4 with
`0.2.0`. All packages share one version ([ADR 0005](adr/0005-single-brand-monorepo-lockstep-versioning.md)).

## Phase gates

Every phase ends with a **gate** item, so that no phase is left with holes before the next one starts
(no "Swiss cheese"). The relay takes a gate only when every other item of its phase is ticked, and it starts no
item of phase N+1 while the gate of phase N is unticked. A gate is a verification, not new development; it
produces a report, `docs/reviews/phase-<N>.md`, and checks:

1. **Completeness.** Every ticked item of the phase is delivered as the item says: the code exists, the public
   API is annotated, the tests and documentation required by the definition of done in `CLAUDE.md` exist
   (package README status, website reference, `CHANGELOG.md`, benchmarks of hot paths), and nothing is a stub, a
   `TODO`, dead code or a silent deviation from the specification.
2. **It works.** From a clean checkout, the full check catalogue (`lua tools/run.lua --list`), the native
   builds, the tests of every package and the examples and benchmark scenarios of the phase pass, and the CI
   workflows are green on the three platforms (Windows excepted where the owner has said so). The exit criteria of the
   phase are demonstrated, not assumed.
3. **Coherence.** Code, ADRs, specifications, package READMEs, the glossary, the roadmap, `docs/open-questions.md`,
   the website (English and French), the catalogue in `automation.md`, `llms.txt`, `README.md` and `CLAUDE.md` say
   the same thing, and nothing says a thing that is not true.
4. **Open questions.** The questions of `docs/open-questions.md` that block the next phase, or that the phase made
   stale, are listed in the report with their context and a recommendation; an issue labelled `needs-decision`
   asks the owner. The relay never decides them.

A gap found becomes a new unticked roadmap item placed before the gate (or a fix inside the gate's pull request
when it is small). The gate is ticked only when the report shows no open gap and every open question it listed
has an owner decision or an explicit, recorded deferral.

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
      (sanitizers on Linux moved to the Phase 1 `native.yml` item, delivered there).
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

- [x] **Phase 0 gate**: verification of the phase, as described in [Phase gates](#phase-gates).

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
      the French translation of those pages (16 pages; terminology in
      `website/fr/glossary-terms.md`), and `check-docs-examples` (code blocks equal their
      tested example files). Still to come, in their own items: tutorials and the other
      packages' guides as the packages land, the translation status check, `hecate doc` for
      user projects, and the `doc` item below.
- [x] `net`: TCP/UDP streams, DNS, buffered readers/writers, TLS (after OQ-4). Micro-benchmarks of its hot paths (`read-until`, `buffered-writer`, `tls-throughput`) landed with the harness item below.
- [x] `json`: codec (after OQ-5). Lua API, yyjson decoder (C), `serde_json` encoder (Rust, OQ-52), corpus and fuzz tests, `bench json`, examples and how-to; native modules built and tested on Linux, macOS and Windows in CI. The native modules in the rockspec and the binary rocks come with release automation (Phase 3). The network benchmark scenarios wait for the harness item below; the micro-benchmark `packages/json/benchmarks/codec.lua` runs with `lua tools/run.lua bench json` and its numbers are measured and published by the owner on dedicated hardware (benchmarks/README.md). Hostile-input costs are open in OQ-54.
- [x] `json` follow-up: remove the pure-Lua backend (OQ-53, closed 2026-10-25): encode failures and `rfc8785` produced by the Rust encoder, no case of the decoder delegated, the oracle replaced by fixtures and property tests, both native modules required at run time everywhere (CI builds them for every package that depends on `json`).
- [x] `doc` (minimal) and the reference generator, **pulled forward from Phase 3** (owner
      decision of 2026-10-13, ADR 0012, Accepted, OQ-11): site build from Markdown and the LuaLS export (`---@class` on every module
      table, `---@param name type description`), generated reference pages for `core` and
      `reactor`, the website built by it in CI. Depends on `json` (the export) and on
      `reactor` (file system, OQ-33), both accepted as dependencies of `doc`; the
      third-party dependencies of ADR 0022 (Accepted) are integrated first.
      Replaces the "website skeleton" item above as the way the site is built; OpenAPI
      reference, versioned documentation, runnable examples and `hecate doc build` for user
      projects stay in Phase 3. Native module (Rust: comrak, syntect) and its
      binary rocks per platform come with release automation (Phase 3, ADR 0021, OQ-41); Lua 5.5
      `global` highlighting (syntect plain variable) and cosmetic code-label cleanups are follow-ups.
- [x] `doc` theme, mobile navigation (owner report, 2026-10-20): the sidebar menu that browses
      the guides, the reference and the other sections cannot be scrolled on mobile devices.
      Fix it in the theme (a long menu scrolls inside its own container, the page behind it
      does not), and add a check on a narrow viewport (a browser test or a documented manual
      check in `docs/architecture/documentation.md`) so that it is not forgotten again.
- [x] `log`: structured logging, RFC 5424 severities, per-scope context (explicit through
      `Logger:with_context`; the implicit propagation across `fork` and `detach` is the next item).
- [x] `reactor` follow-up: ambient context, `reactor.with_ambient(key, value, fn)` and
      `reactor.ambient(key)` ([ADR 0025](adr/0025-ambient-context.md), OQ-55): specify it in
      `concurrency.md`, implement it, test inheritance across `fork`, `detach`, `scope`,
      cancellation and the virtual clock; then give `log` a default context provider and a test
      that a record logged by a forked computation carries the bound context. Needed before
      `kernel` binds the request id.
- [x] Benchmarks harness and first scenario (TCP echo); `benchmarks.yml`. Delivered: `benchmarks/scenarios/tcp-echo`, `benchmarks/run.lua`, `benchmarks/compare.lua`, `bench <scenario> [--compare=ref]`. The Lua load generator replaces `wrk2`/`oha` (no dependency); Micro-benchmarks added for `net` (`read-until`, `buffered-writer`, `tls-throughput`) and `reactor` (`scheduler`). The baseline numbers are measured by the owner on dedicated hardware, and the Phase 1 exit criterion "10 000 concurrent connections on each platform" is verified on Linux and macOS by the scenario; the ADR 0023 accept-spread scenario is the follow-up below (Windows is not a benchmark target, see the vision).
- [x] Benchmarks follow-up: add the multi-process accept-spread scenario of [ADR 0023](adr/0023-multi-process-serving.md) (connections per second and worker spread per strategy), and publish the first baseline measured by the owner. Delivered: `benchmarks/scenarios/accept-spread` (`round_robin`; `reuseport` reported as skipped until OQ-43); baseline measured by the owner on 2026-10-27 at `c75e403` (Ubuntu 24.04 virtual machine on an Intel Core Ultra 7 155H, `round_robin` with 8 workers, 5 000 connections/s for 20 s, 3 invocations of 5 rounds: about 4 980 connections/s, 0 errors, spread 1.00, latency p50 about 1.1 ms and p99 about 185 ms; host noise 1.056 to 1.071, slightly above the 1.05 target), details in the comment on pull request #40; `reuseport` has no baseline until OQ-43. Windows is **not** a benchmark target (owner decision, 2026-10-25: Linux is the only production target, [vision](vision.md)): the network scenarios run on Linux and macOS, and the runner keeps its POSIX shell, `taskset` and `kill`.
- [x] Pin every third-party action of the existing workflows by commit SHA (owner request,
      2026-10-18; [automation.md](architecture/automation.md)); Dependabot keeps them current.
- [x] Workflows `native.yml`, `security.yml`, `nightly.yml`; tasks `sanitize`, `fuzz`,
      `leaks`, `coverage`, `bench`, `check-licenses` (`security.yml`: `cargo audit`,
      `cargo deny`, CodeQL, dependency review, Scorecard).
- [x] `json` follow-up: libFuzzer C targets for the native code of `json`
      (`csrc/native.c`), run by the `fuzz` task and `nightly.yml` (coding-standards.md;
      the `sanitize` task already covers its ASan and UBSan build).
- [ ] `reactor` follow-up (owner decisions of 2026-10-27, OQ-23, OQ-26): `reactor.shield(fn)` with its own deadline, so that cleanup can suspend while its scope is cancelled and a stuck peer cannot block shutdown (then `BufferedWriter:close` flushes, OQ-29); an `on_unobserved_failure` hook for failed detached computations, which `kernel` binds to `log`; `core.IoError` as a base class that `reactor.IoError` extends (`TransportError` stays a sibling).
- [ ] `net` follow-up (owner decisions of 2026-10-27, OQ-47): create a Unix socket inside a `0700` directory (or equivalent) instead of binding then calling `chmod`; `net.listen` binds every resolved address (supersedes OQ-32 point 3); a CRL option for client certificates, and the limit documented until then; separate handshake defaults (10 seconds for `tls.connect` and `connect_tls`, 60 seconds for `tls.accept`, both editable); keep `max_message` editable; a benchmark of the `BufferedWriter` capacity against the 4 KiB default of Go's `bufio` and other frameworks.
- [ ] **Phase 1 gate**: verification of the phase, as described in [Phase gates](#phase-gates). Open
      questions to put to the owner before Phase 2: OQ-50, OQ-47, OQ-23, OQ-24, OQ-26 (1) and OQ-22.

Exit: an echo server handles 10 000 concurrent connections on Linux and macOS (Windows is not a
benchmark target, owner decision of 2026-10-25); structured
concurrency test suite passes; benchmark baseline recorded.

## Phase 2 — HTTP and framework kernel

- [ ] `http`: HTTP/1.1 server (llhttp, OQ-6) and client, message model, streaming,
      keep-alive, limits.
- [ ] `router`: radix tree, URI template subset, 404/405, reverse routing.
- [ ] `schema`: refinement types, composition, coercion, validation with JSON Pointer
      error paths, JSON Schema 2020-12 emission.
- [ ] `container`: IoC container, lifetimes, cycle detection at boot; write its specification section in `docs/architecture/` (OQ-62).
- [ ] `config`: layered configuration validated by schemas; write its specification section in `docs/architecture/`, including the logging keys (OQ-62).
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

- [x] Spike OQ-11 (documentation tooling: site generator and code-reference renderer),
      report with rendered samples submitted to the owner before the website skeleton
      (resolved 2026-10-13: [report](spikes/OQ-11-doc-tooling.md), [ADR 0012](adr/0012-website-generator.md)).

- [ ] **Phase 2 gate**: verification of the phase, as described in [Phase gates](#phase-gates). Open
      questions to put to the owner before Phase 3: OQ-46, OQ-13, OQ-17, OQ-38 and the housekeeping of
      OQ-33 to OQ-36 and OQ-40.

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

- [ ] **Phase 3 gate**: verification of the phase, as described in [Phase gates](#phase-gates). Open
      questions to put to the owner before Phase 4: OQ-18 and OQ-45.

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

- [ ] **Phase 4 gate**: verification of the phase, as described in [Phase gates](#phase-gates).

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

- [ ] **Phase 5 gate**: verification of the phase, as described in [Phase gates](#phase-gates). Open
      questions to put to the owner before Phase 6: OQ-7.

## Phase 6 — Lua 5.4 support

- [ ] Source lowering tool 5.5 → 5.4 ([ADR 0001](adr/0001-lua-5.5-as-sole-target.md)).
- [ ] CI matrix extended to 5.4; publication strategy for 5.4 artefacts (OQ-7).

- [ ] **Phase 6 gate**: verification of the phase, as described in [Phase gates](#phase-gates).

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

- [ ] **Phase 7 gate**: verification of the phase, as described in [Phase gates](#phase-gates).

Exit: every package reviewed, findings resolved or tracked in `docs/open-questions.md`,
CI green on the three platforms.

## Continuous

- Website: French translation kept in sync; further locales by contribution.
- Benchmarks published per release.
