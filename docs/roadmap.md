# Roadmap

Phases are sequential; items inside a phase can proceed in parallel when their
dependencies allow. Each phase ends with explicit exit criteria. Tick items as they land.

Versions: Phases 0–2 produce no release. Phase 3 ends with `0.1.0` (alpha), Phase 4 with
`0.2.0`. All packages share one version ([ADR 0005](adr/0005-single-brand-monorepo-lockstep-versioning.md)).

## Phase gates

Every phase ends with a **gate** item, so that no phase is left with holes before the next one starts
(no "Swiss cheese"). The relay takes a gate only when every other item of its phase is ticked, and it starts no
item of phase N+1 while the gate of phase N is unticked. A gate is a verification, not new development; it
produces a report, `docs/reviews/phase-<N>.md`, and checks the five points below:

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
4. **Safe content (OQ-111).** What the packages of the phase put in error messages, log records, problem details
   and generated documentation is audited (CWE-532): no secret, no credential, no offending input value and no
   personal data, and every field that can carry one is either redacted by name (`log.DEFAULT_REDACT`) or documented
   as never logged. The audit greps the messages and `logger:*` calls of the packages of the phase, runs the canary
   test (a canary secret is put through an error, a log field and a configuration value, and the output is searched
   for it) and lists what it checked in the report; it also checks the production checklist page
   (`website/en/how-to/`) against what the phase added.
5. **Open questions.** The questions of `docs/open-questions.md` that block the next phase, or that the phase made
   stale, are listed in the report with their context and a recommendation; an issue labelled `needs-decision`
   asks the owner. The relay never decides them.

**Triage of minor findings (owner instruction, 2026-11-01).** The relay triages the minor findings of a gate (reviewer
agents, coherence audit) itself and does not put them to the owner. For each, it asks: *does this minor belong to an item
that must be resolved by the end of this gate?* That is, is it a defect of something the phase delivered (a bug, a
missing check, a missing test, a security weakness, a stale or false statement)? If yes, it is fixed directly in the
gate's pull request, test first. If no (it cannot be judged without a measurement or the work of a later phase, such as
a performance finding, or it is a deliberate limit), it is deferred: written into the roadmap item of the later phase that
will handle it, with a pointer to the review row and what to check, or recorded as a known limitation in
`docs/open-questions.md`, so that it is not forgotten. Each row of the review report carries its disposition (fixed with
the commit, or deferred to which item). Owner decisions stay the owner's: an Accepted ADR is never edited, a choice that
nothing decides is made conservatively and recorded in `docs/open-questions.md` for confirmation.

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
- [x] Benchmarks harness and first scenario (TCP echo); `benchmarks.yml`. Delivered: `benchmarks/scenarios/tcp-echo`, `benchmarks/run.lua`, `benchmarks/compare.lua`, `bench <scenario> [--compare=ref]`. The Lua load generator replaces `wrk2`/`oha` (no dependency); Micro-benchmarks added for `net` (`read-until`, `buffered-writer`, `tls-throughput`) and `reactor` (`scheduler`). The baseline numbers are measured by the owner on dedicated hardware, and the Phase 1 exit criterion (10 000 concurrent connections on Linux and macOS) is verified on Linux and macOS by the scenario; the ADR 0023 accept-spread scenario is the follow-up below (Windows is not a benchmark target, see the vision).
- [x] Benchmarks follow-up: add the multi-process accept-spread scenario of [ADR 0023](adr/0023-multi-process-serving.md) (connections per second and worker spread per strategy), and publish the first baseline measured by the owner. Delivered: `benchmarks/scenarios/accept-spread` (`round_robin`; `reuseport` reported as skipped until OQ-43); baseline measured by the owner on 2026-10-27 at `c75e403` (Ubuntu 24.04 virtual machine on an Intel Core Ultra 7 155H, `round_robin` with 8 workers, 5 000 connections/s for 20 s, 3 invocations of 5 rounds: about 4 980 connections/s, 0 errors, spread 1.00, latency p50 about 1.1 ms and p99 about 185 ms; host noise 1.056 to 1.071, slightly above the 1.05 target), details in the comment on pull request #40; `reuseport` has no baseline until OQ-43. Windows is **not** a benchmark target (owner decision, 2026-10-25: Linux is the only production target, [vision](vision.md)): the network scenarios run on Linux and macOS, and the runner keeps its POSIX shell, `taskset` and `kill`.
- [x] Pin every third-party action of the existing workflows by commit SHA (owner request,
      2026-10-18; [automation.md](architecture/automation.md)); Dependabot keeps them current.
- [x] Workflows `native.yml`, `security.yml`, `nightly.yml`; tasks `sanitize`, `fuzz`,
      `leaks`, `coverage`, `bench`, `check-licenses` (`security.yml`: `cargo audit`,
      `cargo deny`, CodeQL, dependency review, Scorecard).
- [x] `json` follow-up: libFuzzer C targets for the native code of `json`
      (`csrc/native.c`), run by the `fuzz` task and `nightly.yml` (coding-standards.md;
      the `sanitize` task already covers its ASan and UBSan build).
- [x] `reactor` follow-up (owner decisions of 2026-10-27, OQ-23, OQ-26): `reactor.shield(limit, fn, ...)` with its own deadline, so that cleanup can suspend while its scope is cancelled and a stuck peer cannot block shutdown (the deadline argument is required, no default decided); an `on_unobserved_failure` hook (`Reactor` option) for failed detached computations, which `kernel` binds to `log`; `core.IoError` as a base class that `reactor.IoError` extends (`TransportError` stays a sibling). `BufferedWriter:close` flushing under the shield (OQ-29) moves to the `net` follow-up below.
- [x] `net` follow-up (owner decisions of 2026-10-27, OQ-47): `BufferedWriter:close` flushes under `reactor.shield` with its own deadline (OQ-23, OQ-29; choose the default and record it); create a Unix socket inside a `0700` directory (or equivalent) instead of binding then calling `chmod`; `net.listen` binds every resolved address (supersedes OQ-32 point 3); a CRL option for client certificates, and the limit documented until then; separate handshake defaults (10 seconds for `tls.connect` and `connect_tls`, 60 seconds for `tls.accept`, both editable); keep `max_message` editable; a benchmark of the `BufferedWriter` capacity against the 4 KiB default of Go's `bufio` and other frameworks. Also Happy Eyeballs (RFC 8305) in `net.connect` (OQ-32 (2), owner decision of 2026-10-27): the next address is tried after about 250 ms in parallel, the first success wins and the others are cancelled. Delivered: every part, with three conservative choices for the owner to confirm (the `close_timeout` default of 5 seconds, the skipping of an unbindable address by `net.listen`, the PEM form of `client_crl_pem`), recorded in OQ-29, OQ-32 and OQ-47; the capacity benchmark is done (`net/buffered-writer`) and the owner chose 16 KiB as the default (2026-11-01).
- [x] **Phase 1 gate**: verification of the phase, as described in [Phase gates](#phase-gates). Open
      questions to put to the owner before Phase 2: OQ-50, OQ-47, OQ-23, OQ-24, OQ-26 (1) and OQ-22. Delivered:
      [report](reviews/phase-1.md): completeness, behaviour, coherence audit (104 findings), the six questions decided by the
      owner, the two follow-up items, the 40 minor findings triaged (31 fixed, the rest deferred into named items),
      and a reviewer wave on the new code and the files nobody had read (security, cross-platform, native code,
      `reactor`, `net`); CI green on the three platforms at the final head. The deferrals are carried by the Phase 2
      benchmarks and `http` items, the Phase 3 `doc` and website items, OQ-65 and OQ-66.

Exit: an echo server handles 10 000 concurrent connections on Linux and macOS (Windows is not a
benchmark target, owner decision of 2026-10-25); structured
concurrency test suite passes; benchmark baseline recorded.

## Phase 2 — HTTP and framework kernel

- [x] `http`: HTTP/1.1 server (llhttp, OQ-6) and client, message model, streaming,
      keep-alive, limits. **Carries three findings deferred from the Phase 1 gate review** (security review,
      [report](reviews/phase-1.md)): (1) map `reactor.TransportError` to a generic RFC 9457 `detail` and never
      forward `context.attempts` or resolved addresses to a client (the `net.connect` error lists every resolved
      address with its errno), with a test; (2) the server owns a limit on concurrent TLS handshakes and runs
      `tls.accept` in a forked computation per connection (a silent client holds a handshake for up to 60 s), and
      bounds the bytes read during a handshake; (3) a production listener passes a numeric address (`net.listen` on
      a name binds every address the resolver lists): decide the default of the `listen` setting and document it.
      **Also carries two items of the llhttp binding review (step 2b)**: (4) the server answers 400 to an HTTP/1.1
      request without exactly one `Host` field (RFC 9112 section 3.2; the parser only exposes the fields); (5) the
      server calls `Parser:close()` when a connection ends, and feeds the parser chunks no larger than its read buffer
      (`feed` returns every event of the chunk in one list).
- [x] `router`: radix tree, URI template subset, 404/405, reverse routing. **Also:** percent-decode each path segment (so `%2F` is not a separator) and resolve dot segments: `request.path` of `http` is raw (OQ-75).
- [x] `schema`: refinement types, composition, coercion, validation with JSON Pointer
      error paths, JSON Schema 2020-12 emission. Decisions OQ-50 and OQ-85 to OQ-97 (OQ-98 lists the choices still to confirm); review and
      fixes in [the review](reviews/schema-review-package.md).
- [x] `container`: IoC container, lifetimes, cycle detection at boot; write its specification section in `docs/architecture/` (OQ-62).
- [x] `config`: layered configuration validated by schemas; write its specification section in `docs/architecture/`, including the logging keys (OQ-62) and the `limits.max_depth` key that lowers the nesting depth of `json` and `schema` together (OQ-92).
- [x] `kernel`: application, modules, controllers, route modules, filters, problem
      details, lifecycle, multi-process workers, graceful shutdown. **Also (from the `schema` review, OQ-98 item 7):** settle how a route names the schema of its response (`docs/developer-experience.md` shows `Class.representation` and an implicit represent; `schema` offers `schema.of(Class):represent(instance)`). **First step (from the `http` reviews):** split
      `packages/http` `server.lua` (options, response writer, connection) and `client.lua` (pool, redirect) with no API
      change; build the in-process dispatch seam (OQ-78, with OQ-76 a), the `on_response` hook (OQ-81) remove the JSON fallback of `Server` for a table (OQ-76 a: an error, a generic 500 and a log entry; OQ-80 decided: no `http.json` or `http.text`) and build the default
      logger of OQ-79 (`log.default()`, console sink on the standard error stream, used by `http` when no `logger` is given, and by `schema` through `package.loaded` when `hecate.log` is already loaded, OQ-86); narrow the type of `Request.content`. **Also (from the `config` item, OQ-101):** (a) add a lowering-only `json.set_max_depth(n)` (it refuses a value above `json.MAX_DEPTH_CEILING` and the value is readable back through `json.DEFAULT_MAX_DEPTH`) and make `schema` read it instead of its constant, then apply `limits.max_depth` (OQ-92); (b) apply the logging keys when building the default logger; (c) pass `hecate.log.Secret` as the `wrap_secret` option of `config.load`.
      **Also (owner decisions of 2026-11-09):** (d) the default logger is built with `log.DEFAULT_REDACT` plus the names of `logging.redact` (OQ-111); (e) the route's response schema is named with `schema.of(Class)` (or any schema), and the kernel itself calls `represent` then encodes (OQ-98 item 7); (f) `Response` content is `string|function|nil` in `http` (the constructor refuses a table), so the kernel gets a helper to answer with a status and a value, for example `hecate.respond(201, user)`, which represents and encodes it by content negotiation; (g) once the kernel has read and validated the content of a request (`Request.content` holds the validated value), `request:stream_content()` and `read_content()` raise a clear `ContentError` ("content already validated and consumed") instead of returning nothing; a route without a body schema keeps the stream untouched. **Also (OQ-112, owner decisions of 2026-11-09):** (h) the configuration key `errors.expose_details` (boolean, default `false`; `true` in the generated `config/development.lua` and `config/test.lua`) makes a 422 entry carry its message and a 500 carry the extension member `debug` (error class, message, traceback), and the kernel logs a `warning` at boot when it is true in the environment `production`; (j) the controller class field `routes = { spec, ... }` (OQ-113 (1)), next to `Controller.route(Class, spec)`, read by `Controller.entries` after `Controller.route` declarations, with its documented limitation (errors surface at boot, not at the line); (k) the options of a route module `hecate.routes(name, { prefix, filters })` (OQ-113 (8)): the `filters` are per-route defaults replaced by the `filters` of a route, the controller `filters` stay a controller-level layer; (l) the configuration key `requests.inputs` (`lax` or `strict`, default `strict`; `lax` in the generated `config/development.lua` and `config/test.lua`) bound to the `inputs` option of the dispatcher (OQ-114 (8)); (m) the rolling reload of the multi-process workers on `SIGHUP` ([ADR 0023](adr/0023-multi-process-serving.md): the primary replaces its workers one at a time with workers running the new code while the old ones drain; OQ-115 (4)), built with the workers; (n) OQ-115: remove the `signals` list option of `Application` (the set is fixed, `signals = false` stays as an opt-out), make a second `sigint` or `sigterm` force the stop, and declare the configuration key `server.grace_timeout` (`config`) bound to `grace_timeout`, with a low value in the generated `config/development.lua` and `config/test.lua`; (i) the problem classes `hecate.problem.*` with `hecate.problem.define`, returnable by an action and raisable from any layer (the guard maps a raised one), referenced by `responses` for the contract and the OpenAPI components.
      **Deferred from this item (owner decisions of 2026-11-11):** the request id bound through the ambient context (`reactor.with_ambient`, `log.bind`; ADR 0025); the binding of `on_unobserved_failure` to `log` (a helper that returns the reactor options belongs to the CLI, Phase 3); the counters of the control protocol (ADR 0023, Decision 5); and the conformance of `reuseport` on three platforms, which waits for luv support (OQ-43). **Also deferred to the Phase 3 CLI:** the generated `config/development.lua` and `config/test.lua` must set `errors.expose_details = true`, `requests.inputs = "lax"` and a low `server.grace_timeout` (2 s, to confirm); `responses.validate` stays a candidate configuration key (OQ-117).
- [ ] Example: `examples/hello` (JSON API with validation).
- [ ] Benchmarks: plaintext and JSON scenarios. **Carries three performance findings deferred from the Phase 1
      gate review** ([review](reviews/phase-1-review-package.md), "Minor"): judge each with a measurement, then
      keep or fix it, and note the result in the review: (RE2) three table allocations per suspend/resume on the
      scheduler hot path (`reactor.lua`, `context.suspend`; scenario `reactor/scheduler`, then `plaintext`);
      (J4) per-key allocation in the Rust encoder (`packages/json/native/src/lib.rs`; `bench json`); (LO4)
      `Logger:with_context` rebuilds the severity list (`logger.lua`; `bench log/logger`). **Also the `router` findings** of
      the 2026-11-02 review (performance-engineer, minor): at least four table allocations per match (segments, values,
      parameters, result), a second tree walk with a set and a list on 404/405 (cache the `Allow` lists per method set),
      the 9-argument recursive `tree.walk`, `rest_of` rescanning segments, the `%%(.?.?)` decode pattern; judge each with
      `packages/router/benchmarks/match.lua` (add a wide fan-out under the matched prefix; static matching drops about
      30 % at 30 000 routes, probably cache effects) and the `plaintext` scenario.
      **Also two `schema` findings** of the 2026-11-08 review ([review](reviews/schema-review-package.md), Performance,
      deferred after fix pass D): (P5) a class-bound build costs about 75 % more than a plain object build (three tables
      and one weak-table insertion; fill the instance directly); (P6) `format` validators cost 0.6 to 1.1 microseconds per
      call. Judge each with `packages/schema/benchmarks/validate.lua` (`build class-bound`, `validate string-email`) and
      the `validation` scenario, on a realistic mix, before touching them.

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

- [ ] Documentation: a how-to page "Before going to production" (`website/en/how-to/`), a checklist of what to verify before an
      application is deployed: log severity, no secrets in error messages (the logger redacts field names, not free text), what the
      default logger and the access log record (query strings), `logging.redact`, secrets declared in `secrets`, limits, development
      mode off. Written after the `kernel` item so that it names its real configuration keys.

- [ ] **Phase 2 gate**: verification of the phase, as described in [Phase gates](#phase-gates). Open
      questions to put to the owner before Phase 3: OQ-46, OQ-13, OQ-17, OQ-38 and OQ-64
      (OQ-33, OQ-35, OQ-36 and OQ-40 were resolved at the Phase 1 gate).

## Phase 3 — Contracts and tooling → `0.1.0`

- [ ] `openapi`: OpenAPI 3.1 assembly, served endpoint, export, contract diff.
- [ ] `test`: test framework, runner, in-process client, fixtures, contract conformance,
      reporters (TAP, JUnit XML), coverage. **Also (T2, from the `http` test review):** a hand-built `Request` whose
      `content` is a table must be JSON-encoded or raise, not read as empty (`Request:read_content` today reads only a
      string); the in-process client uses the dispatch seam of OQ-78. **Also (from the `schema` review, OQ-96):** property-based generators derived from `hecate.schema` types (`generate`, `generate_invalid`, shrinking), which `schema` does not implement.
- [ ] `doc`: project documentation generator for user projects (OpenAPI reference,
      `hecate doc build`); the minimal generator and the code reference moved to Phase 1. **Carries deferrals
      from the Phase 1 gate review** (cross-platform review): refuse, with a `BuildError`, page ids that are not valid
      file names on Windows (`? : * " < > |`, trailing dots or spaces, reserved names such as `CON`) and normalise
      NFC/NFD names before the collision check, because a site is built from a tree authored elsewhere. **Also (from the `schema` review, OQ-96):** the `---@meta` file generation for LuaLS from the schemas of a project (carried here or by `cli`, to settle when `cli` is specified), which `schema` does not implement.
- [ ] `cli` v1: self-contained executable, `new`, `install`, `add`, `remove`, `update`,
      `serve [--watch]`, `test`, `doc`, `contract`, `toolchain`, `doctor`, `version`.
- [ ] Docker images (runtime and build variants, amd64 + arm64).
- [ ] Website: Diátaxis structure, English source, French locale enabled, MDN-like
      theme, getting-started tutorial, reference generated from annotations, built by
      `hecate doc` (ADR 0012, after OQ-11). Pages may be drafted as Markdown earlier.
      **Carries a deferral from the Phase 1 gate:** bring the French pages in step with the English ones (the
      `shield` section of `deadlines-and-cancellation`, the `BufferedWriter:close` and 16 KiB text, the sockets
      how-to, json `out_of_memory`) and refresh every stale `source_revision` stamp (OQ-64; findings A44 and B32 of
      `docs/reviews/phase-1-coherence-findings.md`; row M1 of `docs/reviews/phase-1-review-package.md`).
      **Also carries the French mirror of `http` (Phase 2 item, pull request 52):** translate the six English pages
      `website/en/explanation/http-model.md` and `website/en/how-to/{serve-http, stream-http-content, use-the-http-client,
      http-limits-timeouts-and-tls, handle-forms-and-multipart}.md` (terminology in `website/fr/glossary-terms.md`: add *origin*,
      *head*, *persistent connection*, *pipelining*, *lease*, *grace period*, *action*), stamp their `source_revision`, and check
      that the generated `http` reference (added to `DEFAULT_PACKAGES`) builds in both locales with `--strict`.
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
- [ ] `orm`: data mapper, unit of work, identity map, associations, repositories. **Also (from the `schema` review, OQ-99):** lazy associations must work with `Schema:represent`, which reads the own fields of an instance only and would lose a lazy `__index` field.
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
- [ ] `websocket` (RFC 6455). **Also:** the upgrade takeover with the parser leftover offset, as decided in OQ-76 c (including
      `Connection: close` when an upgrade request is not upgraded, and a security review of that path); the reader
      restructuring of OQ-70 (a client that disconnects during an action) is separate work, not needed by upgrades.
- [ ] HTTP/2.
- [ ] Further NoSQL drivers by demand (e.g. Cassandra/ScyllaDB CQL).

- [ ] `schema`: a decimal type for exact decimal numbers such as money, with a limit on decimal places (OQ-87: `multiple_of` takes integer divisors only; until then integers in minor units, or a string with a pattern).

- [ ] `schema`: a lazy form of `named` for a recursive schema without a class, only if someone needs it (OQ-89: `schema.of(Class)` already closes cycles).

- [ ] **Phase 5 gate**: verification of the phase, as described in [Phase gates](#phase-gates). Open
      questions to put to the owner before Phase 6: OQ-7.

## Phase 6 — Lua 5.4 support

- [ ] Source lowering tool 5.5 → 5.4 ([ADR 0001](adr/0001-lua-5.5-as-sole-target.md)).
- [ ] CI matrix extended to 5.4; publication strategy for 5.4 artefacts (OQ-7).

- [ ] **Phase 6 gate**: verification of the phase, as described in [Phase gates](#phase-gates).

## Phase 7 — Code review and quality pass

- [ ] Sweep the weak assertions of the older `schema` tests (several only assert that a call returned ok; the newer tests cover the same ground more strongly, OQ-99).
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
