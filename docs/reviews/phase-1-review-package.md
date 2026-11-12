# Phase 1 gate: `/review-package` findings

Read-only review of `core`, `reactor`, `net`, `json`, `log` and `doc` (one reviewer agent per package, covering
specification, layering, API, vocabulary, tests, and security, portability and performance where relevant), run on
2026-10-28 at the head of `claude/relay-phase-1-gate`. No blocker. Status column: **open** until fixed in this pull
request (then "fixed <commit>") or moved to a roadmap item. The reviewers could not run every suite (no `luv` or native
build in their sandbox): findings come from reading, and each fix must reproduce the failure first.

## Major

| Id | Package | Finding | Fix |
|---|---|---|---|
| R1 | reactor | `reactor.deadline(math.huge, fn)` arms a timer at infinity; `reactor.lua:338-339` then calls `math.ceil(inf)` and `uv_timer:start` raises, aborting `Reactor:run` (`primitives.lua:354`). Reproduced by the reviewer. | Validate in `deadline` as `sleep` does (decide: `math.huge` = no deadline, or `ArgumentError`); clamp the loop delay (about `2^31` ms). Test with a real clock. **fixed (2026-10-28)** |
| L1 | log | `FileSink` promises line buffering (`logging.md:161`) but the Windows C runtime treats `_IOLBF` as fully buffered (`file_sink.lua:28`). | `flush()` after each write; test reading the file while open. **fixed (2026-10-28)** |
| L2 | log | `Logger` does not validate `context`, `sinks`, `clock`, `name`, `context_provider` (`logger.lua:76-100`); bad values fail later with raw errors on the hot path, contrary to `logging.md:265`. | Raise `ArgumentError` in `init`; copy `context`; tests. **fixed (2026-10-28)** |
| D1 | doc | Home-page `actions` links with a scheme bypass the URL allow-list (`site.lua`, `theme/layout.lua:327`): `javascript:` is emitted. Needs write access to front matter. | Pass scheme targets through `html.is_safe_url`; same for `nav` and `repository` in `config.normalise`; test. **fixed (2026-10-28)** |

## Minor (grouped)

- **core**: malformed interface (`methods` with non-sequence keys) silently accepted (`interface.lua:469`); a finalised
  class can still be overwritten for existing keys (`class.lua:61`, record as a limitation in `open-questions.md`);
  debug traceback starts inside the library and `Error{message=42}` is accepted (`error.lua:46`); trait alias collisions
  and unchecked `alias`/`exclude` shapes (`trait.lua:298,331`); name validation inconsistent across `trait`,
  `interface`, `error_class`; error classes annotated as `hecate.core.Error` (`init.lua:201`); `is_instance_of` lenient
  on a non-class; enumeration values of same-named enumerations compare equal (`value_class.lua:35`); missing tests for
  `__gc`, `finalise` on a trait, alias collisions.
- **reactor**: negative or past deadlines accepted silently (`primitives.lua:354`); three table allocations per
  suspend/resume on the scheduler hot path (`reactor.lua:155-254`); `Reactor:run` clears `context.reactor` before
  closing abandoned coroutines, so a `__close` using the reactor loses its error (`reactor.lua:386-403`). Files not
  reviewed: `tcp`, `udp`, `pipe`, `process`, `ipc`, `fs`, `channel*`, `monitor`, `mutex`, `semaphore`.
- **net**: `TlsStream:write` does not check its argument (`tls_stream.lua:276`, **fixed 2026-10-28**); a `BufferedReader` closed during a
  suspended read still returns the chunk (`buffered_reader.lua:107,264`); hard-coded error levels in validators; unknown
  options in `net.connect`/`listen` reported in `pairs` order (`tcp.lua:54`); `TlsStream:close` skips the session
  close if the inner close raises, and a read racing `close()` gives `TlsError` instead of `EBADF`
  (`tls_stream.lua:343`); README row 16 still cites `concurrency.md` (check against `networking.md`); test gaps listed.
  Native crate, pipe files and `errors.lua` not read.
- **json**: yyjson allocation failure reported as a syntax error (`native.c:301-388`); `size_limit` and BOM failures
  carry a made-up position (`native.c:406`); stale references in OQ-54 and ADR 0020 body ("the two backends", needs
  owner approval of the one-line edit, B10); per-key allocation in the Rust encoder (`lib.rs:388,488`, run `bench json`);
  option values echoed in full in `ArgumentError` (`init.lua:44`); missing tests. Native modules were not built by the
  reviewer, so nothing was run.
- **log**: stale "at any depth" annotation on `redact` (`logger.lua:46`, **fixed 2026-10-28**); public classes typed `table` in `init.lua`;
  no tests for depth 15/16/17 secrets, flush, `AsyncSink:close` with a raising target, option checks; a second
  concurrent `AsyncSink:close()` returns before the drain ends; `with_context` rebuilds the severity list
  (`logger.lua:145`).
- **doc**: `config.normalise` leaves `url`, `exclude`, `outline`, `sidebar`, `strings` unchecked and accepts
  `base = "//host/"`; quoted front-matter scalar with `\\"` accepted (`front_matter.lua`); invalid UTF-8 Markdown gives
  a raw mlua error, not `BuildError`; predictable `luals` temporary directory; `public/` files can overwrite generated
  files; page ids not percent-encoded; `luals.lua` Windows quoting untested; `bin/build.lua` flag parsing; native
  `commonmark` exports the unsafe renderer.

Clean in all six: layering, no globals, vocabulary (`check-glossary`), error-message prefixes.

## Disposition of the minor findings (gate triage, 2026-11-01)

Rule (owner instruction, 2026-11-01, `.claude/commands/relay.md`): a minor that belongs to an item the gate must
resolve (a defect of something Phase 1 delivered) is fixed in this pull request, test first; one that needs a
measurement or a later phase is deferred into that phase's roadmap item, with a pointer back here. Commits are the
short hashes on `claude/relay-phase-1-gate`.

| Id | Finding | Disposition |
|---|---|---|
| C1 | malformed interface accepted | fixed `4fe9e25` |
| C2 | a finalised class can be overwritten for existing keys | deferred: known limitation recorded in `docs/open-questions.md` (OQ-65) |
| C3 | traceback starts inside the library; `Error{message=42}` accepted | fixed `4fe9e25` (also `code` and `context` types) |
| C4 | trait alias collisions, unchecked `alias`/`exclude` | fixed `4fe9e25` |
| C5 | name validation inconsistent | fixed `4fe9e25` (one shared validator) |
| C6 | error classes annotated as `hecate.core.Error` | fixed `4fe9e25` |
| C7 | `is_instance_of` lenient on a non-class | fixed `4fe9e25` (decision: `ArgumentError`, ADR 0018) |
| C8 | same-named enumeration values compare equal | fixed `4fe9e25` |
| C9 | missing tests (`__gc`, `finalise` on a trait, alias collisions) | fixed `4fe9e25` |
| RE1 | negative or past deadlines accepted silently | fixed `c381fe5` (decision: immediate expiry, documented and tested) |
| RE2 | table allocations on the scheduler hot path | measured, kept: removing two tables per suspension gave no significant change ([Phase 2 benchmarks](phase-2-benchmarks.md)) |
| RE3 | `Reactor:run` clears `context.reactor` before closing coroutines | fixed `c381fe5` |
| RE4 | `tcp`, `udp`, `pipe`, `process`, `ipc`, `fs`, `channel*`, `monitor`, `mutex`, `semaphore` not reviewed | reviewed in the reviewer wave below |
| N1 | `BufferedReader` closed during a suspended read returns the chunk | fixed `0d5658b` |
| N2 | hard-coded error levels in validators | no effect: `error` ignores the level for a table value; nothing to fix |
| N3 | unknown options in `pairs` order | fixed `0d5658b` |
| N4 | `TlsStream:close` skips the session close; read racing `close()` | fixed `0d5658b` |
| N5 | README row 16 cites `concurrency.md` | checked: the link is right (`concurrency.md#transport`); wording made precise `0d5658b` |
| N6 | test gaps | fixed `0d5658b` (closed-reader race, TLS close paths, option order) |
| N7 | native crate, pipe files, `errors.lua` not read | reviewed in the reviewer wave below |
| J1 | allocation failure reported as a syntax error | fixed `b28af5c` (reason `out_of_memory`) |
| J2 | `size_limit` and BOM failures carry a made-up position | fixed `b28af5c` (`size_limit` has none; the BOM position is the true one) |
| J3 | stale "two backends" text (OQ-54, ADR 0020) | OQ-54 fixed `b28af5c`; the one sentence of the Accepted ADR 0020 (line 69, the Note) is left: an Accepted ADR is not edited, owner approval needed (proposal: drop the sentence or read "the shared markers are pinned between the decoder and the encoder") |
| J4 | per-key allocation in the Rust encoder | measured, kept: encoding the `kernel-json` document is under 2 % of a request ([Phase 2 benchmarks](phase-2-benchmarks.md)) |
| J5 | option values echoed in full | fixed `b28af5c` |
| J6 | missing tests | fixed `b28af5c` |
| LO1 | public classes typed `table` | fixed `83966dd`, `ac02277` (sinks declared as `hecate.log.Sink`) |
| LO2 | missing tests (depth 15/16/17, raising target) | fixed `83966dd` |
| LO3 | second concurrent `AsyncSink:close()` returns early | fixed `83966dd` (and a never-written sink still closes outside a reactor) |
| LO4 | `with_context` rebuilds the severity list | fixed in the Benchmarks pull request: the child copies the ordinal, about 29 % cheaper ([Phase 2 benchmarks](phase-2-benchmarks.md)) |
| DO1 | `config.normalise` leaves keys unchecked, accepts `base = "//host/"` | fixed `6ef68d9` |
| DO2 | `\\"` accepted in a quoted front-matter scalar | fixed `6ef68d9` |
| DO3 | invalid UTF-8 Markdown gives a raw error | fixed `6ef68d9` (`BuildError` naming the file) |
| DO4 | predictable `luals` temporary directory | fixed `6ef68d9` (`mktemp -d`) |
| DO5 | `public/` files can overwrite generated files | fixed `6ef68d9` (`BuildError`) |
| DO6 | page ids not percent-encoded | fixed `6ef68d9` |
| DO7 | `luals.lua` Windows quoting untested | fixed `6ef68d9` (quoting corrected and tested) |
| DO8 | `bin/build.lua` flag parsing | fixed `6ef68d9` |
| DO9 | native `commonmark` exports the unsafe renderer | fixed `6ef68d9` (cargo feature `spec-tests`, off by default; CI builds the test-only variant: `build-native doc --spec`) |
| M1 | the French pages lack the new text (`shield`, json `out_of_memory`, close behaviour); stale `source_revision` stamps | deferred: `translate` work with the French locale, in the Phase 3 "Website" roadmap item (French locale enabled), together with OQ-64, A44 and B32 of the coherence findings |
