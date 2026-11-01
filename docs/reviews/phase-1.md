# Phase 1 gate report

Date: 2026-10-27, updated 2026-11-01. First pass at `main` 4b478f9 (merge of pull request 40) on Linux (Lua 5.5.1, cargo,
GCC 13.3); final pass at the head of `claude/relay-phase-1-gate` (pull request 47) after the follow-up items and the fixes
below. Windows is not a benchmark target.

Scope: mechanical and behavioural verification (sections 1 and 2), the coherence audit (section 3, details in
[phase-1-coherence-findings.md](phase-1-coherence-findings.md)), the owner decisions on the open questions and their
delivery (section 4), and the follow-up items and the reviewer wave of the end of the gate (section 5, details in
[phase-1-review-package.md](phase-1-review-package.md)).

## 1. Completeness

| Roadmap item | Evidence |
|---|---|
| `core` | `packages/core`, unit tests pass, README status alpha, example `hecate.core.class.lua`, `core/dispatch` micro-benchmark. |
| `reactor` | `packages/reactor`, tests pass (`test`), `reactor/scheduler` micro-benchmark. `offload` is listed as pending in the README and is a Phase 2 item, not a Phase 1 deliverable. |
| Website skeleton, `doc` (minimal), `doc` theme | `check-links`, `check-docs-examples` ok; `build-native doc` ok; doc tests pass. |
| `net` | tests pass; benchmarks `net/read-until`, `net/buffered-writer`, `net/tls-throughput`; examples under `packages/net/examples`. |
| `json` and follow-up | `build-native json` ok; tests pass; `json/codec` benchmark; libFuzzer targets listed by `fuzz --list`. |
| `log` | tests pass; `log/logger` benchmark; `docs/architecture/logging.md`. |
| `reactor` ambient context | covered by the reactor and log tests; `CHANGELOG.md` entry. |
| Benchmarks harness, accept-spread | `bench --list` shows `tcp-echo` and `accept-spread`; `bench tcp-echo` runs 5 rounds with 0 errors; baseline of the owner recorded in the roadmap item. |
| Actions pinned, workflows, libFuzzer | workflows present; CHANGELOG entries present. |

`grep` for `TODO`, `FIXME` and `not implemented` in the Phase 1 package sources (excluding vendored `yyjson`)
finds nothing.

## 2. It works

| Command | Result |
|---|---|
| `check-adr-index`, `check-boundaries`, `check-changelog`, `check-docs-examples`, `check-glossary`, `check-licenses`, `check-links`, `check-lua-constructs`, `check-package-structure`, `check-rockspecs`, `check-versions`, `lint`, `format-check` | ok |
| `build-native json`, `build-native doc` | ok |
| `test` (all packages and `tools`, with `luv` on the path from `luarocks path`) | ok |
| `bench tcp-echo` | ok: 1000 requests/s, 0 errors, p50 about 0.8 ms |
| `typecheck` | not run: `lua-language-server` is absent from the cloud image; it is part of the CI gate list. |
| `sanitize`, `fuzz`, `leaks`, `coverage`, `bench accept-spread` | not run in this pass (CI workflows `native.yml`, `nightly.yml`; accept-spread baseline measured by the owner on 2026-10-27). |

Note for contributors: in the cloud image `luv` is installed under `/opt/lua-5.5` and is found only after
`eval "$(luarocks path)"`; without it `test` reports 66 problems that are not real failures. Worth a line in
`tools/cloud/README.md` (not done here).

Exit criterion "10 000 concurrent connections on Linux and macOS": demonstrated by the `tcp-echo` scenario run
by the owner and by the benchmarks workflow; the local smoke run above uses the default, smaller load.

## 3. Coherence

File-by-file audit in three parts, merged in [phase-1-coherence-findings.md](phase-1-coherence-findings.md): 104 findings
(`core`, `reactor`, `net`; `json`, `log`, `doc`, benchmarks, tools; CI, layering, open questions, roadmap, website).
All small findings were fixed in this pull request. Remaining: owner decisions (D items, listed at the top of that file,
including `check-annotations`, OQ-31 to OQ-42 housekeeping and the ambient-context glossary row) and a few non-blocking
items (A02, A44/B32, C21, C22). Terminology and academic-vocabulary checks (`check-glossary`) pass.

## 4. Open questions for the owner: decided

The owner decided every question of the gate on 2026-10-27 and 2026-11-01 (recorded in `docs/open-questions.md` and
[phase-1-owner-decisions.md](phase-1-owner-decisions.md)); nothing is left open for the gate.

| OQ | Owner decision | Delivery |
|---|---|---|
| OQ-50 typed route content | the presence set (`schema.sent(instance, name)`), not `json.null` as an attribute value | Phase 2 (`schema`, `kernel`) |
| OQ-47 conservative `net`/`reactor` behaviours | answered point by point; Happy Eyeballs added; capacity default 16 KiB (2026-11-01) | the `net` follow-up item, delivered |
| OQ-23 no suspension in cleanup under cancellation | `reactor.shield` with its own deadline | delivered (`reactor` follow-up) |
| OQ-24 strict sibling cancellation | kept | nothing to deliver |
| OQ-26 (1) unobserved `detach` failure; (2) `IoError`; (4) virtual clock | `on_unobserved_failure` hook; `core.IoError` as a base class; real I/O stays refused under the virtual clock | delivered (`reactor` follow-up) |
| OQ-22 absolute deadline instants | confirmed, wall-clock type deferred | until `security` (JWT) or `openapi` needs one |

Choices taken by the relay where nothing was decided, all confirmed by the owner on 2026-11-01: non-finite deadlines
are an `ArgumentError`; `reactor.shield` requires its limit; `BufferedWriter:close_timeout` defaults to 5 seconds;
`net.listen` skips an address failing with `EAFNOSUPPORT`/`EADDRNOTAVAIL` when another is bound; `client_crl_pem` is
a PEM string read once (expiry not enforced, no refresh); Happy Eyeballs keeps the resolver's order; the private
socket directory falls back to bind-then-chmod where hard links are refused, with the cleanup of leftovers documented.

## 5. Follow-up items and the reviewer wave

The two roadmap items placed before the gate are delivered and ticked.

| Item | Evidence |
|---|---|
| `reactor` follow-up | `reactor.shield(limit, fn, ...)`, `Reactor` option `on_unobserved_failure`, `core.IoError`; tests `shield_test.lua`, `unobserved_failure_test.lua`, `error_test.lua`; documented in `concurrency.md`, the README and the website how-to |
| `net` follow-up | handshake defaults (60 s accept, 10 s connect), `BufferedWriter:close` flush under `shield` with `close_timeout`, Unix sockets bound in a private `0700` directory, `net.listen` on every address, `client_crl_pem`, Happy Eyeballs, the `net/buffered-writer` capacity sweep and the 16 KiB default |

**Triage rule** (owner instruction, 2026-11-01, now in `.claude/commands/relay.md` and `docs/roadmap.md`): a minor
finding that is a defect of something the phase delivered is fixed in the gate's pull request, test first; one that
needs a measurement or a later phase is deferred into that phase's roadmap item. The 40 minor findings of the first review were
triaged that way (table in [phase-1-review-package.md](phase-1-review-package.md)): 31 fixed, 2 (the files nobody had
read) reviewed in the wave below, 3 deferred to the Phase 2 benchmarks item (RE2, J4, LO4), 1 known limitation
(OQ-65), 1 deferred to the Phase 3 website item (the French pages), 1 checked and found to have no effect (N2), and
1 sentence of the Accepted ADR 0020 left for the owner (J3).

**Reviewer wave on the end-of-gate code and on the files the first review never read** (security, cross-platform,
native-code, `pkg-reactor`, `pkg-net`; read-only, no blocker). Findings and dispositions:

| Reviewer | Findings | Disposition |
|---|---|---|
| security | teardown mutated the table it iterated; `PipeListener:close` unlinked by name; the link fallback was too broad; the `readable` mode contract; unbounded `shield`; fan-out of Happy Eyeballs; `listen` leaked on a `local_address` error; Windows temporary directory; symlink in `remove_tree`; case collisions | fixed (`d6db7f1`, `15fe38c`, `e6baf1a`); `shield` bound and `readable` documented; the information leak of `context.attempts` and the handshake concurrency cap deferred to the Phase 2 `http` item |
| cross-platform | Windows temporary directory; port collision of `listen` with port 0; case-insensitive collisions; a test leaking a handle; (one finding about the path length was checked and is wrong: `check_path` already rejects it) | fixed (`e6baf1a`, `15fe38c`, `d6db7f1`); Windows-reserved page names and NFC/NFD deferred to the Phase 3 `doc` item |
| native code | **SIGSEGV on deeply nested Markdown** (about 200 KB of `>`); `client_crl_pem` ignored without `client_ca_pem` in Rust; a yyjson document leak on a Lua memory error; a defensive clamp; encoder stack depth untested | fixed (`1e41001`, `e6baf1a`, `aa4841f`); CRL expiry stays unenforced by owner decision (documented) |
| `pkg-reactor` (unreviewed files) | `fs.*` could hang when libuv refuses a request; a failing `register` left a computation suspended; `run_process` left a zombie; NUL in paths; `args` validation; `PipeStream` passed over IPC; and nine minors | fixed (`d6db7f1`); unbounded `run_process` output deferred (OQ-66, needs an API decision) |
| `pkg-net` (unreviewed files) | **`BufferedWriter:__close` could not flush when the computation died from an uncaught cancellation, and replaced the cancellation or deadline error; a write accepted during `close` was dropped**; a poisoned-then-closed writer raised the wrong error; listener leaks; late `server_name` validation; and minors | fixed (`e6ee559`, `15fe38c`); error-context consistency done |

Two of these were defects in code written during this gate (the teardown and the `BufferedWriter` close under
unwinding), found by the reviewer wave and fixed with tests that reproduce them.

## Verdict

**Evidence at the final head:** all check tasks ok; `CI=1 lua tools/run.lua test` ok (every package, the tools tests,
the CommonMark and GFM specification tests against the test-only `spec-tests` build, the JSONTestSuite corpus);
`typecheck` ok with LuaLS 3.19.1 (the release pinned in `ci.yml`, installed under `spikes/`), `sanitize json` ok,
`cargo clippy` clean in the three native crates. CI on the three platforms: green at the final head `cf81412` of pull
request 47 (`ci` on ubuntu, macOS and Windows with Lua 5.5, the three sanitizer jobs, fuzz, CodeQL, markdownlint, links,
build, dependency review and the Rust dependency audit), after the failures of the intermediate heads were fixed (type
checker, `cargo fmt`, two Windows-only tests, the macOS sanitizer jobs).

No gap is open: every finding of the audits and of both review rounds is fixed or deferred into a named roadmap item, every
owner question is decided, and the only owner action left is the optional one-sentence edit of the Accepted ADR 0020
(the Note, line 69, reads "the two backends"; proposal: drop the sentence).
