# Phase 1 gate report

Date: 2026-10-27. Verified at `main` 4b478f9 (merge of pull request 40), on Linux (Lua 5.5.1, cargo, GCC 13.3).
macOS and Windows results are those of the CI runs on `main` (the run on 4b478f9 was still in progress when
this was written; the previous runs, the last one on 25fa7c5, succeeded). Windows is not a benchmark target.

Scope of this pass: mechanical and behavioural verification (sections 1 and 2) and the open questions
(section 4). The file-by-file coherence audit of section 3 and the reviewer agents (`/review-package`) were
**not** run in this pass; the gate therefore stays unticked (see Verdict).

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

Not audited in this pass. Phase 0 showed that the mechanical checks (links, ADR index, generated catalogue,
all ok above) are not a coherence audit.

## 4. Open questions for the owner

| OQ | Context | Recommendation |
|---|---|---|
| OQ-50 typed route content | Concerns `schema` and `kernel`, both Phase 2; no conservative default needed until they are specified. | Defer to the specification of `schema`/`kernel`, early in Phase 2. |
| OQ-47 conservative `net`/`reactor` behaviours | Eight behaviours chosen conservatively on 2026-10-18. | Confirm 1 to 7 as they are; (7) is for a benchmark to settle later; (8) stays tied to OQ-43. |
| OQ-23 no suspension in cleanup under cancellation | `kernel` graceful shutdown and the drivers need to flush while cancelled. | Implement `reactor.shield(fn)` before `kernel`. |
| OQ-24 strict sibling cancellation | Opt-out for supervised work undefined; `detach` is the escape. | Keep it strict; add supervision in `kernel` workers if needed. |
| OQ-26 (1) unobserved `detach` failure is silent | `log` now exists but depends on `reactor`, so `reactor` cannot log directly. | Add an unobserved-failure hook in `reactor` that `kernel` binds to `log`. |
| OQ-22 absolute deadline instants | Needs a wall-clock time type in `core`. | Defer until `security` (JWT) or `openapi` needs one. |

## Verdict

No gap found in the mechanical and behavioural checks. The gate is **not** ticked: the coherence audit and
the reviewer agents are still to run, and the six questions above have no owner decision or recorded deferral.
