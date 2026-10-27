# Phase 1 gate: coherence findings, part B (`json`, `log`, `doc`, benchmarks, tools)

Audit of the "Coherence" check of `docs/roadmap.md` ("Phase gates", item 3), method of
`docs/reviews/phase-0-coherence-findings.md`. Branch `claude/relay-phase-1-gate`, Linux, Lua 5.5.1. Read-only:
nothing was fixed or committed except this file.

## What was read

Read in full (every line):
- `packages/json`: `README.md`, `CLAUDE.md`, `src/hecate/json/{init,errors}.lua`, `internal/backend.lua`, rockspec,
  `native/src/lib.rs` lines 385 to 515 plus every `//!` and `///` comment (by search), `csrc/native.c` comments (by search).
- `packages/log`: `README.md`, `CLAUDE.md`, every file of `src/hecate/log/` (init, severity, record, secret, logger,
  memory/console/file/json_lines/limited/async sinks, `internal/`), rockspec, the three examples, `docs/architecture/logging.md`.
- `packages/doc`: `README.md`, `CLAUDE.md`, `src/hecate/doc/{init,errors,build,highlight,markdown,file_system}.lua`,
  `docs/architecture/documentation.md`.
- `docs/architecture/automation.md`, `tools/README.md`, `tools/CLAUDE.md`, `benchmarks/README.md`, `tools/tasks/bench.lua`,
  `benchmarks/run.lua` (head), `website/en/how-to/{encode-and-decode-json,log-structured-records,measure-performance}.md`,
  `website/fr/how-to/encode-and-decode-json.md`, `CHANGELOG.md` entries on json/log/doc/tools/benchmarks (read; the rest by search).

Read by search or in part only: ADRs 0020 (read), 0021, 0022, 0025 (grep); `docs/open-questions.md` (OQ-46, 52, 53, 54, 55, 56, 60,
61, 62, 63, structure of the file); `docs/roadmap.md` (Phase 1 items); the other `src` files of `doc` (config, site, navigation,
reference, theme, search, luals, system/memory file systems: error messages and DEFAULT_PACKAGES only); doc `native/src/lib.rs`
(alert code only); the headers of `tools/tasks/{build_native,coverage,leaks,sanitize,fuzz,needs,check_licenses}.lua`; `website/fr`
(front matter, diff of each page against its `source_revision`, the log how-to by grep); `.github/workflows/website.yml`
(excerpt); `docs/architecture/{overview,schemas-and-contracts}.md` (json sections); root `README.md`, `llms.txt`, `packages/README.md` (grep).
Not read: JSON tests, `docs/spikes/`, scenario sources other than headers, `benchmarks/lib`, `host-report.sh`,
`tools/tests`, the vendored yyjson, the Rust of `doc` beyond alerts.

Mechanical checks run: `lua tools/run.lua --list` against `automation.md`; glossary deny-list and American-spelling grep over the scope
(no hit outside the glossary rows, the `tools/lib/glossary.lua` table and the serde API identifiers `Serialize`/`serializer`, which are
external names); behaviour probes of the json public API (marked array with a hole, `indent = 17`, duplicate member name, unknown
option, error codes).

Severity: **U** user-facing, **I** internal. Fix size: **S** a few lines, **M** several files, **D** needs an owner decision.

## Summary

32 findings: 16 U, 16 I. By size: 31 S, 1 M (B32), 0 D. Pure-Lua backend: no live statement remains in docs, README, website or CLAUDE
files (the hits are the OQ-53 history and one ADR note, all true); two comments still speak of "every backend" (B09).

## Findings

### json

| ID | Sev | Size | Location | Quoted text | Problem | Fix |
|---|---|---|---|---|---|---|
| B01 | U | S | `packages/json/README.md:104`; `CHANGELOG.md` entry "`hecate.json.native`: the native yyjson decoder binding" ("built by ... or by LuaRocks (`builtin`)"); `packages/json/hecate-json-scm-1.rockspec:19-22` | "`luarocks make` builds the decoder" | The rockspec has `build = { type = "builtin", modules = {} }`: `luarocks make` installs nothing and builds no module. OQ-46 and the roadmap (json item: "come with release automation (Phase 3)") say so. | Replace by "the rockspec does not build the modules yet (OQ-46, release automation, Phase 3); use `build-native json`". Same in the CHANGELOG entry. |
| B02 | U | S | `packages/json/src/hecate/json/errors.lua:283` (`sparse_array`) and `README.md` value-model bullet | "a marked array with a hole or with keys that are not 1 to n" | Untrue for the hole: `json.encode(json.array({1,nil,3}))` gives `[1,null,3]`; `native/src/lib.rs:451-453` raises `sparse_array` only for a non-index key or too many holes (highest index > 2 x entries + 16). | "a marked array with a key that is not a positive integer, or with too many holes (highest index above twice the entries plus 16)". |
| B03 | U | S | `errors.lua:254` and `init.lua:119` | `{ reason: ..., offset: integer, line: integer, column: integer }`; "(with `context.reason`, `offset`, `line` and `column`)" | `duplicate_member_name` carries no `offset`, `line` or `column` (`init.lua:137-139`, README lines 86 and 118). The annotation and doc comment say they are always present. | Make `offset?`, `line?`, `column?` optional in the class and say "absent for `duplicate_member_name`" in `decode` and `DecodeError` comments. |
| B04 | U | S | `docs/architecture/schemas-and-contracts.md:89-90`; ADR 0020 note (line "a `reason`, an `offset`, a `line` and a `column`") | "a `DecodeError` that has a `reason`, an `offset`, a `line` and a `column`" | Same omission as B03 (duplicate member name has none). | Add "except `duplicate_member_name`, which has the reason only". |
| B05 | U | S | `packages/json/README.md:46` (`encode` row) | "`indent` (spaces or a string of spaces and tabs)" | The code limits `indent` to an integer 0 to 16 or a string of at most 16 spaces and tabs (`init.lua:105-108`), and rejects `indent` with `pretty = false` or with `rfc8785`. README states none of it. | State "0 to 16 spaces, or at most 16 characters" and the two conflicts. |
| B06 | U | S | `README.md:51` | "stable codes `hecate.json.*`" | Accurate for the three classes, but the `EncodeFailureReason` and `DecodeFailureReason` tables are documented only for `decode` (README 84-91). Reasons `syntax`, `invalid_escape`, `control_character` (decode) and the whole set `unsupported_type`, `non_finite_number`, `ambiguous_table`, `sparse_array`, `integer_out_of_range`, `invalid_utf8`, `depth_limit`, `size_limit` (encode) are absent from the README and from the website how-to, which links to the README table for "reasons". | Add an "Encode failures" table (reason, input, fix) and list the three missing decode reasons. |
| B07 | I | S | `packages/json/README.md:11` vs `README.md:16-17` | status "alpha — ... expected-output fixtures" ; "Specification: schemas-and-contracts.md" | Fine, but the `Decisions` row omits OQ-48 to OQ-54, which `CLAUDE.md:20` cites; the README cites OQ-53 and OQ-54 in prose. Minor; the two files should name the same owner decisions. | Add the OQ list to README "Decisions" or drop OQ-48/49/51 from CLAUDE.md. |
| B08 | I | S | `errors.lua:2` | "one error hierarchy, whatever backend does the work" | Suggests several interchangeable backends; there are exactly two native modules and no choice (OQ-53). | "one error hierarchy; both native modules report through it". |
| B09 | I | S | `internal/markers.lua:1-2`, `internal/position.lua:2` | "The value model shared by every backend", "every backend reports the offset only" | Same: the vocabulary "backend" survives only as the name of the seam (`internal/backend.lua`). | "shared by the decoder and the encoder". |
| B10 | I | S | `docs/adr/0020-json-yyjson-decoder-serde-encoder.md` "Verification" (the paragraph "pin the shared markers between the two backends") and `markers.lua` | "between the two backends" | The ADR's own note (2026-10-25) says it now reads "the decoder and the encoder" but the body was left unchanged, so the Accepted ADR contradicts its note. | Edit the sentence in place and keep the note. |

### log

| ID | Sev | Size | Location | Quoted text | Problem | Fix |
|---|---|---|---|---|---|---|
| B11 | I | S | `packages/log/src/hecate/log/file_sink.lua:153-154` | "asynchronous flushing is a later step" | `AsyncSink` exists and is documented (README 52, logging.md 181-212). | "wrap it in an `AsyncSink` to move the write off the caller". |
| B12 | U | S | `packages/log/README.md:61` | "## Layout (once implemented)" | The package is implemented (status alpha). Also the status row starts "step 1" for a package that lists four steps. | "## Layout"; drop "step 1:" from Status. |
| B13 | U | S | `packages/log/README.md:46,56-59` vs `docs/architecture/logging.md:125-129,235-245` | README Public API table has no row for `log.bind` | `log.bind` is the one non-class function besides `Severity`/`severity_code` and has a `---@param` annotation; it appears only in prose after the table. | Add a table row `log.bind(fields, fn, ...)` with its two error classes (`ArgumentError`, `NonYieldableContextError`). |
| B14 | U | S | `README.md:46` (`redact`: "any depth") vs `logging.md:262,277` | "case-insensitive, any depth" / "any depth up to 16 levels" | The code stops at `MAX_REDACT_DEPTH = 16` (`logger.lua:14,23`); the README, website how-to (line 53-54) and CHANGELOG say "any depth" with no bound. Spec and README disagree. | Say "up to 16 levels" in README and how-to. |
| B15 | U | S | `website/en/how-to/log-structured-records.md:77-81`; example `packages/log/examples/hecate.log.AsyncSink.lua:1-2`; `packages/log/benchmarks/logger.lua:34` | "a detached coroutine writes to the target", "drain coroutine", "drain task" | README and logging.md call it the **drain computation** (glossary: computation = what `detach` starts); "task" is a glossary "instead of" term. Three names for one concept. | Use "drain computation" in the how-to, the example comment (the how-to embeds it, so `check-docs-examples` needs both changed) and the benchmark comment. |
| B16 | U | S | `CHANGELOG.md` entry "`hecate.log`, step 1" (line 33) | "`Logger` with a threshold", "a detached task driven by a `Semaphore`", "Open points in OQ-55 (the reactor has no ambient context yet; decided in ADR 0025, to be implemented)"; also line 32 "a task that is gone" | "threshold" is forbidden by glossary and OQ-60 ("never level or threshold"); "task" likewise; the OQ-55 remark is untrue since the ambient context is implemented (CHANGELOG line 18). | Reword: "severity", "computation"; delete the OQ-55 sentence. |
| B17 | U | S | `website/fr/how-to/log-structured-records.md:36` | "Les sévérités sont les huit de la RFC 5424" | `website/fr/glossary-terms.md:59`: severity = gravité, "jamais « niveau » ni « sévérité »". | "Les gravités sont les huit de la RFC 5424". |
| B18 | I | S | `docs/open-questions.md:96` and `:81-95` | `| OQ-63 | \`log\`, qualified message prefix ...` as the last line of the file | The row sits after the "OQ-55 addendum" and "OQ-56" prose sections, outside any table, so it renders as a stray line and OQ-63 is not in the "Resolved" table it belongs to (it is decided, "no new decision"). OQ-55 also has no entry of its own, only an addendum, though `logger.lua:188`, ADR 0025 and the roadmap cite "OQ-55" (phase-0 F37 flagged the duplicate id). | Move the OQ-63 row into "Resolved"; give OQ-55 a real row or reword the citations to ADR 0025. |
| B19 | I | S | `packages/log/README.md:3`, `init.lua:1`, `CLAUDE.md:8`, rockspec summary, `packages/README.md`, `llms.txt:54` | "per-scope context" | Documented exception (logging.md:229-230, phase-0 F02) but the package's own README never uses or links "ambient context" (ADR 0025), the term of `log.bind` and of `reactor`. A reader finds two names with no pointer in the README. | Add "(the ambient context of ADR 0025)" once in the README Responsibilities line "context propagation through reactor scopes". |
| B20 | I | S | `README.md:51` (`FileSink`) vs `file_sink.lua:187-189` | "a failed write raises `hecate.core.Error`" | Accurate; but `FileSink:write` after `close` silently returns (logging.md:161 says so, the README does not). | One clause in the README row. |

### doc

| ID | Sev | Size | Location | Quoted text | Problem | Fix |
|---|---|---|---|---|---|---|
| B21 | I | S | `packages/doc/README.md:48-49` | "the first slice below has none, and the candidates are measured in spike OQ-39" | Untrue: the package now has third-party dependencies (comrak, syntect, two-face; README line 15 and ADR 0022 Accepted). Also `documentation.md:118-119` "the proposal is ADR 0022" while the same file's header says Accepted. | Rewrite both as "decided in ADR 0022 (Accepted)". |
| B22 | U | S | `docs/architecture/documentation.md:58` | "callout containers (`note`, `tip`, `warning`, `danger`)" | Callouts are GFM alerts NOTE, TIP, IMPORTANT, WARNING, CAUTION (README 120, `markdown.lua:35`, CHANGELOG). Also `markdown.lua:18` and `site.lua:187` call the fifth label `danger` for a CAUTION alert (`native/src/lib.rs:52`, `strings.lua:46,91` "Danger"), and `site.lua:187` passes no `important` label although `markdown.lua:18` lists one. | State the five alerts; name the label `caution` (or document that `danger` is the title of CAUTION) and pass `important`. |
| B23 | U | S | `packages/doc/README.md:11,138` and `:136` | "Limits of this first slice", "Phase 1 roadmap item" with "Roadmap phase 3" at line 10 | The table says phase 3 and the status says the minimal slice is done in Phase 1; the section name "first slice" survives the native-module rewrite. Not wrong, but the same package carries both labels. | "Limits of the current implementation"; keep phase 3 and say why in Status. |
| B24 | I | S | `packages/doc/src/hecate/doc/{build.lua:29,33,38,49,92; config.lua:43; front_matter.lua:13,82; luals.lua:76; site.lua:60,73; system_file_system.lua:23}` | e.g. `"cannot read site configuration " .. path`, `"invalid front matter at line 1: ..."` | The rule (phase-0 F34, OQ-63, coding-standards "Errors"): messages carry the qualified `module.function:` prefix. `json` and `log` follow it; these `doc` messages do not (others in `doc` do: `doc.build:`, `doc.Site:`). | Add `doc.load_config:`, `doc.build:`, `doc.front_matter.parse:` ... prefixes, or record the exception in OQ-63. |
| B25 | I | S | `packages/doc/README.md:63` | "`BuildError` ... `strict` problems" | Also raised for `SystemFileSystem` failures (`system_file_system.lua:23`) and LuaLS export failure (`luals.lua:75`); README lists only three causes. Minor. | Add the two causes. |
| B26 | U | S | `website/en/reference/index.md:12-17`, `website/fr/reference/index.md:17-20` | list of `core`, `reactor`, `net`, `json` only | `reference_site.DEFAULT_PACKAGES` is `core, reactor, net, json, log` (`reference_site.lua:16`, README 110), the home page says `log` is "implemented and documented", and a log how-to links to it. The reference index has no `hecate.log` entry. Also `.github/workflows/website.yml:118-121` checks only `core reactor net`. | Add the `hecate.log` line (EN and FR) and `json log` to the workflow loop. |
| B27 | I | S | `tools/tasks/gen_reference.lua:4`; `docs/architecture/automation.md` row `gen-reference` | "gen-reference [--packages core,reactor,net]"; "done for `core`, `reactor`, `net`" | The default set is now `core, reactor, net, json, log`; `packages/doc/bin/reference.lua:13` and `bin/build.lua:21` add only `json` (not `log`) to `package.path`, harmless because LuaLS reads the source, but the automation row is stale. | Update both texts. |

### tools, automation catalogue, benchmarks

| ID | Sev | Size | Location | Quoted text | Problem | Fix |
|---|---|---|---|---|---|---|
| B28 | I | S | `docs/architecture/automation.md` section 1 (no row), `lua tools/run.lua --list` line `build-native` | (absent) | The catalogue does not list `build-native` (the only one of the 31 listed tasks missing; every other `--list` task has a row). `CLAUDE.md` and the README of json cite it as a command. | Add a row: `build-native <package>`, done, cargo or `cc`, installs into `.hecate/rocks`. |
| B29 | I | S | `automation.md` rows `format` / `format-check` and `check-annotations` | "formatter on Lua sources (and `clang-format` on C)"; `check-annotations` status "P1" | `--list` says "no formatter configured for the repository (OQ-3); always succeeds" and `CLAUDE.md` says the same. `check-annotations` is marked P1, no such task exists and Phase 1 is complete (ADR 0018 still cites it). | Rewrite the format row as a no-op until OQ-3; retime `check-annotations` (Phase 2 or an explicit deferral) and record it in the gate report. |
| B30 | I | S | `automation.md` row `bench` ; `tools/tasks/bench.lua:122` (`description`) | "`bench [name...] [--list] [--runs=N] [--pin=CPUS] [--out=DIR]`" | The task also takes `--yes`, `--strict`, `all` and the scenario form (`--rounds`, `--server-pin`, `--load-pin`, `--server-args`, `--compare`); the `--list` description lists neither. `benchmarks/README.md:53,75` uses `--rounds` for scenarios and `--runs` for micro-benchmarks, which no document explains. | One sentence in automation.md and in the task description: `--runs` for files, `--rounds` for scenarios. |
| B31 | U | S | `benchmarks/README.md:4`, `:10`, `:22`, `:92` | "their history is published on the website"; "`tcp-echo` ... 10 000 concurrent connections"; "memory, allocations per request"; "a C compiler, `cmake` and `cargo`" | (a) automation.md (`benchmarks.yml` row) says the history "comes later"; nothing is published. (b) The load generator defaults to 100 connections (`scenarios/tcp-echo/load.lua:24`) and the workflow uses 1000; 10 000 is only the documented example. (c) the scenarios print latency, throughput and errors only; no memory or allocation measure. (d) `cmake` is used by no task (`grep` over `tools/`). | (a) "will be published"; (b) "up to 10 000"; (c) "memory and allocations: not measured yet"; (d) drop `cmake`. |
| B32 | I | M | `website/fr/**` front matter `source_revision` | e.g. `how-to/log-structured-records.md:6` `ac925c3`; `reference/index.md` `cba7be6`; `index.md` `f1f3b5e` | 12 of 17 French pages are older than the English source by `git diff` (e.g. 4 lines of the log how-to, one line of the reference index, 7 of the home page). I compared the content of the pages in scope (json, log, index, how-to index, reference index) and they are in sync apart from B17; the revision stamp is what is stale, so `check-translations` (Phase 3) will flag them all. | Bump `source_revision` to the commit at which each page was last reconciled (after fixing B17), or record the deferral. |

## Checked and found coherent

- `lua tools/run.lua --list` against the catalogue: the 31 tasks other than `build-native` have a row, and the descriptions of `sanitize`,
  `fuzz`, `leaks`, `coverage` (core, reactor, router, schema at 90 %, `tools/lib/coverage.lua:6`), `needs`, `check-licenses`,
  `fetch-fixtures` agree with their sources (B28 to B30 excepted). `fuzz --list` gives `json decode`, `json decode_limits` and the `net` targets as the catalogue says.
- json: `README.md` signatures, options and defaults (`max_depth` 1000, `max_size` 16 MiB, `canonical`, `rfc8785`), `duplicate_member_name`
  (OQ-61), error codes `hecate.json.*`, the load error message naming `lua tools/run.lua build-native json`, the 40-byte echo,
  the `-0` behaviour and the native comments (`native.c`, `lib.rs`) agree with the code. The three website examples are the tested files and
  the French page equals the English one.
- log: all option names, defaults, sink behaviours, error classes and messages in `logging.md` match the code (checked sink by sink);
  the severity vocabulary (`severity`, never `level`) is applied in the source, README, how-to and spec; OQ-60, OQ-61, OQ-62 match the code.
- British spelling and the glossary deny-list: no violation in scope beyond B15, B16.
