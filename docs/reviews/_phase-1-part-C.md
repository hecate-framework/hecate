# Phase 1 gate: coherence audit, part C (cross-cutting files)

Branch `claude/relay-phase-1-gate`, Linux, read-only audit. Coherence = every concept is named and described
identically everywhere, and nothing says something untrue.

## What was read (read this first)

Read in full: `docs/roadmap.md`, `docs/open-questions.md`, `docs/vision.md`, `docs/architecture/overview.md`,
`docs/architecture/automation.md`, `docs/architecture/concurrency.md`, `docs/adr/README.md`, `README.md`,
`AGENTS.md`, `CONTRIBUTING.md`, `llms.txt`, `packages/README.md`, `docs/README.md`, `HANDOFF.md`,
`website/site.lua`, `website/README.md`, `website/OUTLINE.md`, the English index pages (`index.md`,
`how-to/index.md`, `explanation/index.md`, `reference/index.md`), `.claude/commands/relay.md`, `bench.md`,
`translate.md`, `write-docs.md`, `implement-task.md`, `check.md`, the head of `phase-0-coherence-findings.md`
(method), and the first 60 lines of `packages/reactor/README.md`. `CLAUDE.md` was read as given in the task.

Read in part or by search only: `docs/architecture/{logging,object-model,documentation,ai-assisted-development,
testing,versioning-and-distribution,cli-and-packaging,schemas-and-contracts,http-and-routing,data-access,
coding-standards}.md` (status lines, "implemented / not implemented / Phase N" statements, identifiers),
the ADRs (status lines and cross-references only), all rockspecs (dependencies), `require` calls of every
package with a `src/`, `tools/tasks/check_boundaries.lua`, `tools/lib/lint.lua`, the 10 workflows (triggers and
`tools/run.lua` calls), `.github/labels.yml` and `labeler.yml`, the French pages (structure comparison with the
English ones: headings, code fences, links, `source_revision` against `git log`; prose not read line by line),
`.claude/agents/*` and `packages/*/CLAUDE.md` (dependency lines, paths, task names, stale phrases),
`packages/doc/bin/*.lua`, `reference_site.lua`, `.gitignore`.

Mechanical checks run, all passing: `check-boundaries`, `check-adr-index`, `gen-catalogue --check`,
`gen-dependency-graph --check`, `gen-llms-txt --check`, `check-links`, `check-versions`,
`check-package-structure`, `check-changelog`, `check-glossary`, `check-rockspecs`. Every `OQ-NN` written
anywhere in the repository (highest 63) has an entry or section in `docs/open-questions.md`; every `ADR NNNN`
(0001 to 0026) exists and its status in prose agrees with the index (one exception, C14). Every
`lua tools/run.lua <task>` written in `.claude/`, `docs/`, READMEs, workflows exists. Every path in
`.claude/` and `CLAUDE.md` exists. `require` calls of `core`, `json`, `log`, `net`, `reactor`, `doc` match
the rockspec dependencies. `packages/*/CLAUDE.md`, READMEs and rockspecs agree on dependencies for all 29
packages. French and English pages: same 16 pages, same headings, fences and links (one link differs, C21).
Not covered: package READMEs beyond the lines quoted, the `website` prose, ADR bodies, `docs/spikes/`.

Severity: **U** user-facing, **I** internal. Fix size: **S** a few lines, **M** several files, **D** needs the
owner first.

## Summary

27 findings (C01 to C27): 2 U, 25 I. By size: 24 S, 3 D (C03, C17, C18). Plus six "not findings" notes (one M: French `source_revision` stamps).

## Findings

### CI, tasks and automation

**C01 — I / S — `.github/workflows/ci.yml:277` vs `docs/architecture/automation.md:99`.**
`automation.md`: "format-check, lint, typecheck, check-* (including `check-docs-examples` and `check-licenses`),
unit tests". `ci.yml` loops over `check-versions check-rockspecs check-package-structure check-docs-examples
check-licenses typecheck`, then `lint` and `test`. No workflow runs `check-boundaries`,
`check-lua-constructs`, `check-glossary`, `check-adr-index`, `check-changelog`, `check-links`, `format-check`
or the three `gen-* --check` (grep over `.github/` finds none; `docs.yml` runs lychee, not `check-links`).
The layering, ADR 0001 constructs and glossary rules that `CLAUDE.md` calls non-negotiable are therefore not
enforced by CI, and `automation.md` says they are.
Fix: add the missing tasks to the loop (Linux is enough for the pure-Lua ones), or correct the row. Prefer the
first.

**C02 — I / S — `docs/architecture/automation.md` (catalogue), `tools/CLAUDE.md:10`.**
`build-native` is in `lua tools/run.lua --list` and used by `ci.yml`, `nightly.yml`, `CLAUDE.md`, but is not in
the catalogue; `tools/CLAUDE.md:10` says "Every new task: add it to the catalogue table in automation.md".
Fix: add a row under "Tests and measurements" (or a new "Native" group).

**C03 — I / D — `docs/architecture/automation.md:37`, `docs/adr/0018-error-signalling.md:50`.**
the `check-annotations` row: every exported symbol has LuaLS annotations; functions that suspend carry the `@async` annotation
The table marks it P1. The task does not exist (`--list`), no roadmap item delivers it, and Phase 1 is complete. The
definition of done ("public API annotated") and ADR 0018 (nullable returns) rely on it. `lint` only checks
that a chunk compiles and declares its globals (`tools/lib/lint.lua:2-4`).
Fix: owner decision: add a roadmap item before the gate, or move it to a named later phase and drop the P1.

**C04 — I / S — `docs/architecture/object-model.md:74`.**
"The linter (Phase 0 tooling) reports external access to `_`-prefixed members." `tools/lib/lint.lua` has two
rules (compiles; globals declared). No such rule exists. Same overclaim in `automation.md:31`
("linter rules from coding-standards.md").
Fix: say "planned" in both, or implement the rule.

**C05 — I / S — `docs/architecture/automation.md:30`.**
"`format` / `format-check` | formatter on Lua sources (and `clang-format` on C) | done". Both tasks are
no-ops (`--list`: "no formatter configured for the repository (OQ-3); always succeeds"; `CLAUDE.md` says the
same).
Fix: "no-op until a formatter supports Lua 5.5 (OQ-3)"; "done" is misleading.

**C06 — I / S — `docs/architecture/automation.md:15, 21-24, 99, 103, 108`.**
Legend: "`done` = implemented ... `P0` = to write in Phase 0". Phase 0 is ticked, yet the bootstrap rows and
`ci.yml` remain `P0`; `website.yml` is "P2; first version done ... translation status and `hecate doc`
pending". Status vocabulary mixes planned phase and delivery state.
Fix: set `done` where delivered; keep `P<n>` only for what is not.

**C07 — I / S — `docs/architecture/automation.md:72, 103`.**
Line 72: `gen-reference ... | done for core, reactor, net`; `DEFAULT_PACKAGES` in
`packages/doc/src/hecate/doc/reference_site.lua:16` is `core, reactor, net, json, log`. Line 103: "`hecate doc`,
or the interim generator chosen after OQ-11": OQ-11 is resolved (ADR 0012), the generator is `packages/doc/bin/build.lua`.
Fix: update both.

**C08 — I / S — `.github/workflows/website.yml:119`.**
"for package in core reactor net; do test -f website/dist/en/reference/$package/index.html" checks three of the
five generated packages (`json`, `log` unchecked).
Fix: add `json log`.

**C09 — I / S — `.claude/commands/check.md:8-10`, `tools/hooks/pre-commit.lua:2`.**
`check.md` lists 10 tasks and "If a task does not exist yet, say so": all exist, and the list omits
`check-changelog`, `check-rockspecs`, `check-docs-examples`, `check-licenses` (listed in `CLAUDE.md`
"Other gates") and the `gen-* --check`; the roadmap gate wants the "full check catalogue". The pre-commit
comment "no-op until OQ-3 is resolved": OQ-3 is resolved (no formatter for now).
Fix: align `check.md` with `CLAUDE.md`; reword the hook comment.

**C10 — I / S — `docs/architecture/ai-assisted-development.md:85`.**
"Phase 0 replaces the setup script with the pinned bootstrap." Phase 0 is done (roadmap `[x]`).
Fix: past tense, or drop.

### Layering and overview

**C11 — I / S — `docs/architecture/overview.md:5-6` (and `CLAUDE.md`, "a lower layer").**
"A package may depend only on packages of strictly lower layers". The generated graph (same file) and the
rockspecs have same-layer edges: `log --> json`, `log --> reactor`, `net --> reactor` (layer 1),
`security --> kernel`, `template --> kernel` (layer 3), `sql --> query`; `check_boundaries.lua` rejects only
`rank[d] > rank[name]` (upward), i.e. same layer is allowed.
Fix: "lower or same layer, no cycle", or define sub-layers.

**C12 — I / S — `docs/architecture/overview.md:97` vs `docs/open-questions.md:13` (OQ-45).**
"Hashing for auth protocols (SHA-256, HMAC, PBKDF2) | provided by the TLS library binding | OQ-4".
OQ-45 states OQ-4's assumption is false: the `net` native module exposes only TLS sessions, and the home of
these primitives is an open decision.
Fix: replace by "undecided, OQ-45".

### Open questions

**C13 — I / S — `docs/open-questions.md:96`.**
The resolved row `| OQ-63 | ...` sits after the `### OQ-56` section (lines 89-95), so it is outside the
"Resolved" table and renders as stray text.
Fix: move it into the table (after OQ-62).

**C14 — I / S — `docs/open-questions.md:81-95`, `docs/roadmap.md:122`, `docs/adr/0025-ambient-context.md`.**
OQ-55 has no entry anywhere, only an "addendum" that refers to "Point (1) of OQ-55"; OQ-56 is a section, not a
table row. Eight references to OQ-55 and eight to OQ-56 point to nothing a reader can find in a table. IDs are
otherwise consecutive 1 to 63.
Fix: add OQ-55 and OQ-56 rows to "Resolved" (outcome: ADR 0025, `with_ambient`/`ambient`) and fold the two
sections into them.

**C15 — I / S — `docs/open-questions.md:54` (OQ-8, Resolved).**
"Remaining: the `reactor` primitives (roadmap, Phase 2) and OQ-43". The primitives are delivered
(`docs/roadmap.md:165`, `[x]`).
Fix: "Remaining: OQ-43".

**C16 — I / S — `docs/open-questions.md:14` (OQ-46).**
"every package rockspec except `core` has `modules = {}`". `packages/core/hecate-core-scm-1.rockspec:21` also
has `modules = {}`; all 29 do. Also "`check-rockspecs` does not notice" is the real point.
Fix: drop "except `core`" (and "(fails today for every package but `core`...)").

**C17 — I / D — `docs/open-questions.md:28-34, 26, 33` (OQ-33, 34, 35, 36, 40, 31).**
Entries still in the open "decision" table although the owner decided and the work is implemented, and some
contradict themselves: OQ-33 says "`hecate.json` has no source yet" and then "Implemented: `hecate.json`
replaced the in-house encoder"; OQ-40 (1) "`hecate.json` has no source yet", (6) "only `hecate.core.class`,
`hecate.reactor.sleep` and `hecate.net.connect` exist" (`packages/*/examples` now holds 21 files), (2)
"alternative: commit them" vs `.gitignore`; OQ-31, OQ-33, OQ-40 "verified on Linux only until CI runs on
macOS and Windows" (CI runs on the three). The Phase 2 gate calls them "housekeeping" (`roadmap.md:176`).
Fix: owner to resolve each; then move to "Resolved" with the surviving open points only.

**C18 — I / D — `docs/roadmap.md:137-138` (gate item 4).**
The Phase 1 gate lists OQ-50, 47, 23, 24, 26 (1), 22. Other Phase 1 `decision` entries that say "implemented
conservatively" and await confirmation appear in no gate list and have no phase: OQ-25, OQ-29, OQ-30, OQ-32,
OQ-42 (and OQ-31 above). OQ-50 is a Phase 2 question (`schema`, `kernel`), not one the phase made stale.
Fix: owner to confirm, resolve or record a deferral for each; the gate wording requires it.

**C19 — I / S — `docs/open-questions.md:12` (OQ-43, "Blocks").**
Column: "`reactor`, `kernel`". Text: "**Not urgent:** ... nothing is blocked while it is open". Same pattern for
OQ-46 (`all packages, release`, conservative default is to leave it).
Fix: "none (optimisation)".

### Roadmap wording

**C20 — I / S — `docs/roadmap.md:95` and `:127` vs `:140-141`.**
Line 95: "the French translation of those pages (13 pages ...)": 16 pages exist (`website/fr`). Line 127:
'the Phase 1 exit criterion "10 000 concurrent connections on each platform" is verified on Linux and macOS';
the exit criterion at line 140 reads "on Linux and macOS". The quoted criterion no longer exists.
Fix: "16 pages"; drop the quotation or requote it.

**C21 — I / S — `docs/roadmap.md:161-177`.**
A second heading "Phase 2 — additional spike" holds two ticked items (the delivered `reactor` multi-process
primitives, the OQ-11 spike, resolved on 2026-10-13, before Phase 1's `doc` item) and the Phase 2 gate, after
the Phase 2 "Exit" paragraph. The gate is not last in its phase and the spike belongs to Phase 1 history.
Fix: merge under Phase 2, keep the gate last, move the OQ-11 spike into Phase 0/1.
(Related: `website/fr/how-to/udp-pipes-and-dns.md` has one link fewer than the English page,
`run-processes-and-pass-connections.md`, verified by link diff.)

**C22 — I / S — `packages/README.md:24` and `packages/doc/README.md:10` vs `docs/roadmap.md:103-108`.**
`doc` is catalogued as Phase 3, `alpha`; the roadmap pulled its minimal slice and the generator into Phase 1
(ticked), and Phase 3 keeps the user-project generator. A reader of the catalogue sees an alpha package in a
phase not started.
Fix: Phase 1 in the README table (the catalogue is generated from it), or a note "minimal slice in 1, rest in 3".

### Status statements

**C23 — I / S — `CLAUDE.md:7-9`.**
"Phase 0 and most of Phase 1 of the roadmap". Every Phase 1 item is ticked (only the gate is open).
Same stale "foundations ... other packages are still specifications" is accurate but unversioned in
`CONTRIBUTING.md:3` and `llms.txt:5-6`; `README.md:34-39` is correct.
Fix: "Phases 0 and 1 (gate pending)".

**C24 — U / S — `README.md:66` and badge `README.md:13`, vs `docs/vision.md:40-43`.**
README: "Cross-platform. Linux, macOS and Windows are first-class targets." (badge "first-class"). Vision (owner
decision 2026-10-25): "Linux is the only production target. macOS and Windows are development platforms."
The public README states the opposite of the vision.
Fix: "Linux is the production target; macOS and Windows are supported development platforms, tested in CI."

**C25 — I / S — `docs/architecture/concurrency.md:47-48` vs `docs/open-questions.md:20` (OQ-23).**
"`<close>` variables and `finally`-style cleanup run normally." OQ-23: cleanup cannot suspend while its scope is
cancelled (level-triggered cancellation), and `BufferedWriter:close` discards unflushed bytes because of it.
Fix: add "but cannot suspend (OQ-23)". The primitives table (lines 21-34) omits `detach`, implemented and
named in rule 2.

**C26 — I / S — `docs/architecture/documentation.md:35`.**
"Produced by `hecate doc` (Phase 3; a bootstrap script in `tools/` before that)". The bootstrap entry points
are `packages/doc/bin/build.lua` and `packages/doc/bin/reference.lua`; `tools/` only wraps them
(`gen-reference`).
Fix: name `packages/doc/bin/`.

### Website and glossary

**C27 — U / S — `website/en/reference/index.md:10-20` (and `fr`), `.gitignore:29-32`, `website/OUTLINE.md`.**
`DEFAULT_PACKAGES` generates a `log` reference (`reference_site.lua:16`), and `website/en/index.md` says
"core, reactor, net, json and log packages are implemented and documented", but the reference landing page
(both languages) lists only core, reactor, net, json, so `log` reference pages are unreachable from it; the
generated `website/en/reference/log/` is not in `.gitignore` (the other four are), so it can be committed by
accident. `OUTLINE.md` omits the pages that exist: "Encode and decode JSON", "Measure performance" (the
"Logging and request context (P2)" entry has no file, though `how-to/log-structured-records.md` exists).
Fix: add `log` to both reference indexes and `.gitignore`; list the three pages in `OUTLINE.md`.

## Not findings, but to know

- **Translation freshness.** In 11 of 16 French pages `source_revision` is older than later English commits
  (for example `how-to/index.md`: 6 English commits since; `explanation/multi-process-serving.md`: 3). The
  French file was last committed with the English one in each case and structure matches, so the content is
  probably in step, but the stamp is wrong and `check-translations` (Phase 3) would flag them all.
  `website/fr/README.md` claims "Chaque page ... porte `source_revision`". Fix when convenient: bump the stamps
  after a reading of each pair (M).
- **Ambient context is not in the glossary** (`docs/glossary.md` has no row, though ADR 0025 and OQ-56 say "There
  is no second name" and `log` has an `ambient` module). The phase-0 audit decided "ambient" is a scope, but it is
  now an API concept (`reactor.with_ambient`, `reactor.ambient`). Candidate row, S.
- **ADR status vs history.** `CHANGELOG.md:62` says "Proposed ADR 0023"; it is Accepted (history of an
  unreleased entry, S). OQ-58 is "resolved by the owner" while ADR 0026 is still `Proposed`
  (`docs/adr/README.md:40`): consistent with CLAUDE.md (only the owner promotes), but the owner should promote it
  or the OQ-58 row should say so.
- **Benchmark baseline** ("benchmark baseline recorded", Phase 1 exit): the accept-spread numbers live only in
  `docs/roadmap.md:128` and a pull request comment; `benchmarks/README.md:178` says only "measured by the owner".
  The `tcp-echo` baseline is not recorded in a file either (`docs/reviews/phase-1.md:22` points to the roadmap).
  Decide where baselines live (S, D).
- **docs/README.md** table omits `reviews/` and `spikes/`.
