# Phase 2 gate: coherence findings

Audit of the "Coherence" check of `docs/roadmap.md` ("Phase gates", item 3) for Phase 2, method and format of
[phase-1-coherence-findings.md](phase-1-coherence-findings.md). Scope: the Phase 2 packages `http`, `router`,
`schema`, `container`, `config`, `kernel`, `hecate` (meta-module, partial), the `reactor` follow-ups (`offload`,
the multi-process primitives of ADR 0023), `examples/hello`, the benchmark scenarios `plaintext` and `kernel-json`,
and everything that speaks about them. Branch `claude/relay-phase-2-gate`, Linux. Nothing was fixed, nothing
committed; this file is the only change.

The README statuses of the Phase 2 packages were set to `alpha` in this branch on purpose (gate finding G2) and the
`gen-* --check` tasks were added to CI (G1): both are taken as given.

## What was read, and how

Read in full: the root `CLAUDE.md`, `README.md`, `llms.txt`; `docs/glossary.md`; the Phase 2 sections and the
"Phase gates" section of `docs/roadmap.md`; `docs/reviews/phase-2.md`; the README of `http`, `router`, `schema`,
`container`, `config`, `kernel`, `hecate` and their `CLAUDE.md`; `docs/architecture/overview.md`,
`http-and-routing.md`, `automation.md`; `docs/developer-experience.md`; ADR 0006 and 0023;
`examples/README.md`, `examples/hello/README.md` and `main.lua`; `packages/hecate/src/hecate/init.lua` and its
rockspec; `website/en/index.md`, `website/fr/index.md`, the four index pages of `website/en` and `website/fr`;
`website/OUTLINE.md`, `website/README.md`; `benchmarks/README.md` (scenario table and the HTTP and accept-spread
sections).

Read in part, or by search: `docs/architecture/configuration.md`, `container.md`, `logging.md`, `concurrency.md`
("Workers"), `schemas-and-contracts.md` (status, violation codes); `docs/open-questions.md` (the open table in full
at 120 characters a row; rows OQ-70, 75, 77, 78, 82, 84, 101, 116 and 117 in full); `CHANGELOG.md` (`[Unreleased]`,
the Phase 2 entries); `website/en/how-to/http-limits-timeouts-and-tls.md` (the limits table),
`configure-an-application.md` (keys), `explanation/multi-process-serving.md` and its French copy ("What exists
today"); `.claude/agents/pkg-*.md` of the seven packages ("Allowed dependencies"); `.github/workflows/ci.yml` and
`benchmarks.yml` (the task loops and the scenario matrix).

Checked against the code (not from memory): `Server.DEFAULTS` and `Client.DEFAULTS` (`http/server.lua`,
`http/client.lua`, `internal/server_options.lua`) against the README, the specification and the limits page (all
equal); the `Router` options (`router.lua`); the 26 violation codes (`schema/violation.lua`) against the
specification table (equal); the framework keys and their defaults (`config/declaration.lua`) against the config
README and `configuration.md` (equal); the defaults of `Supervisor` and `Application` (`restart_delay` 0.1,
`crash_limit` 5, `crash_window` 60, `ready_timeout` 30, `grace_timeout` 30, `problems.MAX_ERRORS` 100) against the
kernel README (equal); the response-validation message (`kernel/results.lua:166-168`); `json.set_max_depth` and its
use at boot (`kernel/application.lua:215,265`); `log.default()` and `log.DEFAULT_REDACT` (`log/init.lua:57-80`);
`DEFAULT_PACKAGES` of the reference (`doc/reference_site.lua:18`); the re-exports of `hecate` (`init.lua`).

Mechanical checks run (`eval "$(luarocks path)"` first): `check-links`, `check-glossary`, `check-docs-examples`,
`check-adr-index`, `gen-catalogue --check`, `gen-llms-txt --check`, `gen-dependency-graph --check`: all ok. The
task list of `lua tools/run.lua --list` was compared name by name with `automation.md`: every existing task is
catalogued; the catalogue names three P2 tasks that do not exist (C11). The public glossary was compared with
`docs/glossary.md` by first column. Not run: `typecheck` and the website build (the generated reference was not
inspected).

Severity: **major** a false statement a user or an agent would act on (public README, website, specification,
`CLAUDE.md`), or a gap that needs an owner decision; **minor** a stale or incomplete statement whose truth is
elsewhere and easy to restore. Fix kind: **text** (a small text edit in the gate's pull request) or **decision**
(needs the owner, or work of a later phase recorded in the roadmap).

## Summary

32 findings: 8 major (C1, C3, C7, C9, C10, C11, C18, C20), 24 minor. By fix kind: 28 text, 4 decision (C10, C11,
C25, C32). Nothing contradicts an Accepted ADR in the code except the default worker count of the
future CLI (C32, recorded as an open-question proposal, the ADR is not to be edited). The numeric defaults, option
names, error reasons and violation codes checked agree between code, READMEs, specifications and the English
website. The main pattern: the project-level status lines (`CLAUDE.md`, `README.md`, `llms.txt`, website home in
both languages) still describe the end of Phase 1, and several specifications keep a "not yet implemented" that the
`kernel` item resolved.

The five findings that matter most: C1, C3, C7, C11, C20.

Disposition (fix pass of the gate's pull request): the text findings are fixed, except C24 and C29, whose files
(`packages/http/README.md`, `CHANGELOG.md`) were edited by another agent at the same time; the four decision
findings (C10, C11, C25, C32) go to the owner in section 5 of the [gate report](phase-2.md). The last column of each
table gives the disposition of each finding.

## Findings

### 1. Project status statements

| ID | Severity | Location | What is inconsistent | Source of truth | Proposed fix | Fix | Disposition |
|---|---|---|---|---|---|---|---|
| C1 | major | `CLAUDE.md:7-9` | "the foundations are written (`core`, `reactor`, `net`, `json`, `log`, `doc`; Phases 0 and 1 of the roadmap, both gates done). The other packages are still specifications." `http`, `router`, `schema`, `container`, `config` and `kernel` are implemented (alpha) and `hecate` is in progress; an agent reading this would treat them as unwritten. | Code; `packages/README.md` (statuses); `docs/roadmap.md` (Phase 2 items ticked) | "...written (`core`, `reactor`, `net`, `json`, `log`, `doc`, then `http`, `router`, `schema`, `container`, `config`, `kernel` and part of `hecate`; Phases 0 to 2 of the roadmap, the Phase 2 gate in progress). The other packages are still specifications." Update again when the gate is ticked. | text | Fixed |
| C2 | minor | `CLAUDE.md:116-118` | "Tooling does not exist yet; it is built in Phase 0 as Lua tasks..." The tasks exist and the section below lists them. | `lua tools/run.lua --list`; roadmap Phase 0 ticked | "Tooling is a set of Lua tasks run by `lua tools/run.lua <task>` (catalogue: `docs/architecture/automation.md`)." and drop "Fill this section as soon as each command is available". | text | Fixed |
| C3 | major | `README.md:34-39` | The note says "The HTTP server, router, schemas, kernel, tooling and data access are specified in `docs/` and not written yet". The HTTP server and client, router, schemas, container, configuration and kernel are implemented and tested on three platforms (CI of eb9d9b7). | Code; `packages/README.md`; roadmap | List the Phase 2 packages among what exists ("...the HTTP server and client (`http`), the router, schemas, the container, configuration and the kernel with multi-process workers"), and say that OpenAPI, the test framework, the CLI and data access are not written yet. | text | Fixed |
| C4 | minor | `llms.txt:5-6` | "Status: early implementation (foundations written, other packages still specifications)." Same as C1; the hand-written part of `llms.txt` is not regenerated by `gen-llms-txt` (only the package list between the markers). | `packages/README.md` | "Status: early implementation (runtime, HTTP stack, schemas, configuration, container and kernel written; OpenAPI, test framework, CLI and data access still specifications)." | text | Fixed |
| C5 | minor | `llms.txt:34-47` ("Website pages") | The list stops at the Phase 1 pages and the offload guide. Missing: how-to `serve-http`, `stream-http-content`, `use-the-http-client`, `handle-forms-and-multipart`, `http-limits-timeouts-and-tls`, `route-requests`, `validate-with-schemas`, `use-the-container`, `configure-an-application`, `before-going-to-production`; explanation `http-model`, `schemas-and-contracts`. `website/CLAUDE.md` asks to "regenerate `llms.txt`" after adding a page; `website/OUTLINE.md` lists all twelve. | `website/en/` (the files exist); `website/OUTLINE.md` | Add the twelve lines with the one-line descriptions of `website/en/how-to/index.md` and `explanation/index.md`. | text | Fixed |
| C6 | minor | `llms.txt:18-31` ("Architecture") | The list omits `docs/architecture/container.md` and `configuration.md`, the two specifications written in Phase 2 (OQ-62). | `docs/architecture/` | Add a "Container" line (`docs/architecture/container.md`: bindings, lifetimes, service scopes, boot validation) and a "Configuration" line (`docs/architecture/configuration.md`: layers, environment variables, secrets, framework keys). | text | Fixed |
| C7 | major | `website/en/index.md:16-21`; `website/fr/index.md:17-21` | Home page note: "The core, reactor, net, json and log packages are implemented and documented [...] Everything else is still specified and not implemented." The same site documents `http`, `router`, `schema`, `container`, `config` and `kernel` (ten how-to pages, two explanation pages, reference sections); the French note says the same. | Code; `website/en/reference/index.md` (lists the eleven documented packages) | English: "The core, reactor, net, json, log, http, router, schema, container, config and kernel packages are implemented and documented [...] OpenAPI, the test framework, the CLI and data access are still specified and not implemented." French: the same sentence, then bump `source_revision`. | text | Fixed |
| C8 | minor | `website/fr/reference/index.md:13-24` | The French reference index lists ten packages and omits `hecate.http`, which the English index lists (`website/en/reference/index.md:19`) and `DEFAULT_PACKAGES` generates (`packages/doc/src/hecate/doc/reference_site.lua:18`). | `reference_site.lua:18`; English page | Add the `hecate.http` line between `hecate.log` and `hecate.router` (translated from the English line). | text | Fixed |

### 2. Website, outline and public glossary

| ID | Severity | Location | What is inconsistent | Source of truth | Proposed fix | Fix | Disposition |
|---|---|---|---|---|---|---|---|
| C9 | major | `website/en/reference/glossary.md` (tables "Types and validation" and "HTTP") | The public glossary, which `website/README.md` says to "keep in step" with `docs/glossary.md`, lacks the 14 terms added in Phase 2: `violation`, `class-bound schema`, `presence set`, `work budget`, `validator`, `build`, `Representable`, `represent`, `fail-fast mode`, `minor units`, `union (sum type)` (`docs/glossary.md:122-132`) and `path template`, `route table`, `dot segment` (`docs/glossary.md:152-154`). The how-to and explanation pages of `schema` and `router` use these terms and link to the glossary. (The French glossary lags further; its catch-up is the Phase 3 French item.) | `docs/glossary.md` | Add the 14 rows to the English public glossary (adapted like the other rows); leave the French copy to the Phase 3 translation item and name these rows there. | text | Fixed |
| C10 | major | `website/OUTLINE.md:23,24,26,33,52,62,63,64,71,72,73` | Pages marked "(P2)" that do not exist and that no roadmap item carries: how-to "Problem details: mapping domain errors", "Filters", "Concurrency: fork/join...", "Background work and offloading" (now covered by the offload page, `:32`, so a duplicate), "Multi-process deployment, graceful shutdown, health checks"; reference "Configuration keys", "Error codes", "Schema keywords and formats"; explanation "Architecture and layers", "The object model", "Concurrency model". The outline says a marker is the "roadmap phase in which the page must exist" (`:3`), so by its own rule Phase 2 is incomplete; the roadmap has no Phase 2 website item. | `docs/roadmap.md` (precedence 4 over the outline, which is not a source of truth at all) | Owner choice: re-mark these pages P3 (the reference pages depend on the generators of C11; the filters and problem pages fit the Phase 3 tutorial work) and add them to the Phase 3 website item, or add a Phase 2 item before the gate. Remove the duplicate "Background work" line. | decision | Owner (section 5 of the report) |
| C11 | major | `docs/architecture/automation.md:78-80`; `docs/adr/0018-error-signalling.md:46` | The catalogue marks `gen-error-codes`, `gen-config-reference` and `gen-meta` as **P2**; none exists (`run.lua --list`), no roadmap item carries them, and Accepted ADR 0018 states "Every error class and code is documented on the website (`gen-error-codes`)". Same pattern as Phase 1 finding C03 (`check-annotations`). | Code (`--list`); roadmap | Owner choice: move the three tasks to P3 (the `doc` and `cli` items; `gen-meta` is already "carried by `doc` or `cli`" in `packages/schema/README.md:28,87`) and name them in those roadmap items, or add a Phase 2 item. ADR 0018 is not edited: its statement stays true once the task exists. | decision | Owner (section 5 of the report) |
| C12 | minor | `docs/architecture/automation.md:103` (`ci.yml` row) | "(`check-links`, `check-changelog` and the `gen-* --check` tasks are not run by CI yet)". `ci.yml:150-154` and `:495-499` now run `gen-catalogue`, `gen-llms-txt` and `gen-dependency-graph --check` in `docs-checks` and in the Linux static checks. The list of static checks in the same row also omits `docs-checks` running `check-adr-index`, `check-docs-examples`, `check-examples`, `check-package-structure`. | `.github/workflows/ci.yml` | "(`check-links` and `check-changelog` are not run by CI yet; the `gen-* --check` tasks run in the static checks and in `docs-checks`)". | text | Fixed |
| C13 | minor | `docs/architecture/automation.md:76` (`gen-reference` row) | "done; default set `core`, `reactor`, `net`, `json`, `log`". The default set has eleven packages, the Phase 2 ones included. | `packages/doc/src/hecate/doc/reference_site.lua:18` | "done; default set: the eleven packages of `reference_site.DEFAULT_PACKAGES` (Phases 1 and 2)". | text | Fixed |
| C14 | minor | `docs/architecture/automation.md:62` (`bench` row) and `:106` (`benchmarks.yml` row) | `:62`: "the `plaintext`, `json` and later scenarios come with their packages", status "P1 (partly done...)". `plaintext` and `kernel-json` exist (the JSON scenario is named `kernel-json`). `:106`: "P1 (delivered for `tcp-echo`...)", while `benchmarks.yml:43-48` also compares `plaintext` and `kernel-json` at 2 000 requests per second. (The `--runs` versus `--rounds` confusion is gate finding G3.) | `benchmarks/scenarios/`; `benchmarks.yml` | `:62`: "the `plaintext` and `kernel-json` scenarios exist (Phase 2); `validation` and `routing` are listed in the roadmap section Continuous"; `:106`: "delivered for `tcp-echo`, `plaintext` and `kernel-json`". | text | Fixed |

### 3. Specifications behind the code

| ID | Severity | Location | What is inconsistent | Source of truth | Proposed fix | Fix | Disposition |
|---|---|---|---|---|---|---|---|
| C15 | minor | `docs/architecture/http-and-routing.md:3`; sections "`hecate.kernel`" (`:106-163`) | "Status: specification." for three implemented packages (Phase 1 finding A09, same pattern for `concurrency.md`, was fixed). `http` and `router` have an "Implemented surface" section; the kernel section has none, so the only description of the delivered kernel (options bound to configuration keys, `respond`, problem classes, `Accept` with `406`, the `422` entry shape with `source`) is its README. | Code; `packages/kernel/README.md` | "Status: implemented in Phase 2 (alpha); a statement about something not implemented says so." Add a short "Implemented surface" to the kernel section that points to the README for the full API (as the router section does). | text | Fixed |
| C16 | minor | `docs/architecture/schemas-and-contracts.md:3` | "Status: specification." `schema` is implemented (alpha); `openapi` is not. | Code | "Status: `schema` implemented in Phase 2 (alpha; the section "Generation" is not implemented); `openapi` specification (Phase 3)." | text | Fixed |
| C17 | minor | `docs/architecture/configuration.md:3` and `:263-266` | `:3` "Status: specification, implemented in phase 2" (two statuses glued). `:264-266` say the kernel now applies `limits.max_depth` through `json.set_max_depth`, then end with "Until the kernel applies the key at boot, it is validated and reported only (OQ-101)": contradictory; the kernel applies it (`kernel/application.lua:215,265`). | Code | `:3`: "Status: implemented in Phase 2 (alpha)". `:266`: delete the last sentence. | text | Fixed |
| C18 | major | `packages/config/README.md:47` | "`limits.max_depth` is validated and exposed but has no effect on `hecate.json` and `hecate.schema` until the kernel item adds a setter to both (OQ-101, kernel handoff)." The kernel item is done: `Application:boot` applies it through `json.set_max_depth` and `schema` reads it. A user would conclude the key does nothing. | Code; `configuration.md:263-265`; roadmap kernel item (a) | "`config` does not apply `limits.max_depth` itself: `kernel.Application` applies it at boot (`json.set_max_depth`, read by `schema`)." | text | Fixed |
| C19 | minor | `docs/architecture/logging.md:339-341` and `:252` | `:340-341`: "Keys of `hecate.config` for logging [...] applied by the kernel, not yet implemented." Implemented by `hecate.kernel.logging.build` and `Application` (kernel README, "`hecate.kernel.logging`"). `:252`: "Today a logger is configured in code only." | Code (`packages/kernel/src/hecate/kernel/logging.lua`) | `:341`: "applied by the kernel (`hecate.kernel.logging.build`) when an `Application` has a configuration". `:252`: "A `Logger` is configured in code; the kernel builds the default logger from the logging keys (below)." | text | Fixed |
| C20 | major | `docs/architecture/logging.md` (no occurrence of `log.default`, `log.set_default` or `DEFAULT_REDACT`) | The specification does not describe the process-wide default logger delivered in Phase 2 (OQ-79, OQ-111): `log.default()` (console sink on standard error, `informational`, `redact = log.DEFAULT_REDACT`), `log.set_default`, and the 19 names of `log.DEFAULT_REDACT`. `http`, `schema` (through `package.loaded`, OQ-86) and `kernel` rely on it; the log README (`:48-49`) and the code (`log/init.lua:57-80`) have it. A specification is above a README in precedence, so today the spec is silent on a public, security-relevant default. | Code; OQ-79, OQ-111 (resolved); `packages/log/README.md:48-49` | Add a section "The default logger" to `logging.md` (what it writes, where, at which severity, the redaction list and that it is matched by exact name only, `set_default`, who uses it, how the kernel replaces it from the logging keys). | text (decision only if the redaction list is to be reviewed) | Fixed |

### 4. Package READMEs and agent files

| ID | Severity | Location | What is inconsistent | Source of truth | Proposed fix | Fix | Disposition |
|---|---|---|---|---|---|---|---|
| C21 | minor | `packages/kernel/README.md:34` | Non-goal: "the meta-module `hecate` [...] belongs to the `hecate` package, which has no code yet". `packages/hecate/src/hecate/init.lua` re-exports the kernel surface, and `examples/hello` uses it. | Code; `packages/hecate/README.md` (status "in progress") | "...belongs to the `hecate` package (it re-exports `Application`, `Controller`, `routes`, `respond`, `problem`, `load_configuration` and the kernel errors)". | text | Fixed |
| C22 | minor | `packages/kernel/README.md:254-255` (Layout) | Lists `tests/unit/ tests/integration/ tests/fixtures/` and `examples/ benchmarks/`; `packages/kernel` has no `examples/` and no `benchmarks/` (it has `tests/helpers/`). Every other Phase 2 package has `examples/`; the kernel's measured hot path is the repository scenario `benchmarks/scenarios/kernel-json`. | `ls packages/kernel` | List what exists (`tests/unit/ tests/integration/ tests/fixtures/ tests/helpers/`) and say "benchmark: `benchmarks/scenarios/kernel-json`; tested example: `examples/hello`". Whether the kernel needs `examples/<symbol>.lua` files for the generated reference (coding-standards.md) is a completeness question for section 1 of the gate report. | text | Fixed |
| C23 | minor | `packages/hecate/README.md:50-55` | Heading "Layout (once implemented)" and the layout `tests/unit/ tests/integration/ tests/fixtures/ examples/ benchmarks/`; the package is implemented in part and has only `src/hecate/init.lua` and `tests/unit/`. | `ls packages/hecate` | Heading "Layout"; list `src/hecate/init.lua` and `tests/unit/` (a re-export completeness test). | text | Fixed |
| C24 | minor | `packages/http/README.md:51` | "`http.serve_request(action, request)` (*may suspend*, needs no socket and no native module: name provisional, OQ-78)". OQ-78 is resolved and the owner chose the name on 2026-11-09 (`docs/open-questions.md:91`). | OQ-78 (resolved) | Drop "name provisional," and cite "OQ-78, resolved". | text | Fixed (by the relay) |
| C25 | minor | `docs/open-questions.md:60` (OQ-117, resolved, choice 4) | "a mismatch raises `hecate.core.ValidationError` [...] whose message names the status, the pointer and the code of the first violation". The code names the status, the number of violations and the first code, deliberately without the pointer (`kernel/results.lua:166-168`; `CHANGELOG.md`, `[Unreleased]`: "the response-validation message names the status and the violation code, not the pointer into the data"; kernel README `:197`). The recorded owner decision and the code differ. | The owner's decision text (OQ-117) versus code; the change is a safety tightening after OQ-111 | Do not rewrite the decision silently: add a dated note to OQ-117 ("the message omits the pointer since the kernel review, OQ-111; to confirm") and list it in section 5 of the gate report for the owner. | decision (confirmation) | Owner (section 5 of the report) |
| C26 | minor | `packages/container/README.md:24` | "lifetimes: singleton (per process), scoped (per reactor scope, e.g. request), transient". A scoped service lives in a **service scope** (`container:open_scope()`), which the container ties to no reactor scope; the kernel opens one per request (`request.services`). | `docs/architecture/container.md` ("Lifetimes", OQ-105) | "scoped (per service scope; the kernel opens one per request)". | text | Fixed |
| C27 | minor | `docs/glossary.md` ("Object model and architecture") | "service scope" is a term of the Phase 2 API (`container.ServiceScope`, `open_scope`, `request.services`, kernel README `:157-159`, `container.md`) and is easy to confuse with the reactor "scope" (glossary `:45`), which C26 shows happening; the glossary does not define it. | `container.md` ("Lifetimes"); ADR 0004 (vocabulary is recorded in the glossary) | Add a row "service scope: the region in which a `scoped` service has one instance (`Container:open_scope`); the kernel opens one per request as `request.services`; not a reactor scope". Mirror it in the public glossary (C9). | text | Fixed |
| C28 | minor | `.claude/agents/pkg-kernel.md` ("Working rules") | "Allowed dependencies: `hecate.core`, `hecate.reactor`, `hecate.log`, `hecate.http`, ..." omits `hecate.net`, which `packages/kernel/CLAUDE.md` allows (ADR 0027, Accepted) and the kernel requires for the listening strategies. | ADR 0027; `packages/kernel/CLAUDE.md` | Add "`hecate.net` (ADR 0027)". | text | Fixed |

### 5. Changelog, benchmarks, roadmap and ADRs

| ID | Severity | Location | What is inconsistent | Source of truth | Proposed fix | Fix | Disposition |
|---|---|---|---|---|---|---|---|
| C29 | minor | `CHANGELOG.md:51`, `:58`, `:309` (`[Unreleased]`) | Entries use names and states that no longer hold: `HandoffListener` (`:51`, `:309`; now `HandOverListener`), the log code `handover_queue_full` (`:309`; now `hand_over_queue_full`), "`kernel` now depends on `net` (ADR 0027, Proposed)" (`:51`; Accepted), "options `signals`, a list or `false`" (`:58`; now `true` or `false`, OQ-115). Same pattern as Phase 1 finding A18: one `[Unreleased]` list for a never-released version, where a reader cannot tell which names exist. | Code; `docs/adr/README.md` | Rewrite the four entries with the current names (the history stays in git), or fold the superseded entries into the later ones that rename them. | text | Fixed (by the relay, in `CHANGELOG.md`) |
| C30 | minor | `benchmarks/README.md:14-15` | The `validation` and `routing` scenarios are in the Phase column as **2** ("not written yet"); the roadmap places them in "Continuous" (`docs/roadmap.md:397-398`), not in Phase 2. | `docs/roadmap.md` | Phase column: "continuous (roadmap)". | text | Fixed |
| C31 | minor | `docs/roadmap.md:175` and `:228` | Two headings "Phase 2 — HTTP and framework kernel" and "Phase 2 — additional spike"; the second holds delivered work items (offload, multi-process primitives, the production checklist page, the examples rules) and the Phase 2 gate, while the first holds the Phase 2 exit criteria. Phase 1 finding C21, left undone. | `docs/roadmap.md` (structure of the other phases) | Merge the second list into the first, before the exit line, keeping the gate last. | text | Fixed |
| C32 | minor | `docs/adr/0023-multi-process-serving.md` Decision 1; `docs/architecture/concurrency.md` ("Workers", first bullet) | ADR 0023 (Accepted) and the specification: "`hecate serve --workers N` (default `uv.available_parallelism()`, the number of CPU cores)". The configuration key `server.workers` and the `Application` option `workers` default to 1 (`config/declaration.lua`, OQ-116 (1)). Not a contradiction today (the CLI is Phase 3), but the CLI item will have to reconcile a flag defaulting to the cores with a key defaulting to 1, and OQ-116 does not mention the ADR's default. | ADR 0023 (Accepted, not to be edited); OQ-116 (owner decision) | Record in `docs/open-questions.md` (or in the Phase 3 `cli` item): "`hecate serve` without `--workers`: CPU cores (ADR 0023) or `server.workers` (default 1, OQ-116)? Which wins?" | decision | Owner (section 5 of the report) |

## Checked and found consistent

- `http`: the server and client defaults, per-request client options, the limits table (README, specification,
  `how-to/http-limits-timeouts-and-tls.md`) and the code.
- `router`: options and defaults, `RouteTableError` reasons, the layout.
- `schema`: the 26 violation codes (spec table and `hecate.schema.ViolationCode`), the layout.
- `config`: the framework keys, defaults and reserved names (README, `configuration.md`, code).
- `kernel`: supervisor and application defaults, `MAX_ERRORS`, the `inputs` policy, `validate_responses` default
  (OQ-117 (1)), the multi-process sections of `concurrency.md` and of the explanation page (English and French), the
  examples README (`HELLO_PORT`, `HELLO_WORKERS`, 10 s grace period in `main.lua`).
- `overview.md` dependency graph (generated, `--check` ok) and the ADR index (`check-adr-index` ok).
- `benchmarks.yml` runs `plaintext` and `kernel-json` at 2 000 requests per second, as `benchmarks/README.md` says.
- `packages/README.md` and the `llms.txt` package list (generated, `--check` ok).
