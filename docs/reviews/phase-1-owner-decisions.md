# Phase 1 gate: decisions for the owner

Companion of [phase-1.md](phase-1.md) and [phase-1-coherence-findings.md](phase-1-coherence-findings.md).
Each entry gives the context, the evidence, the options and a recommendation. Nothing here is decided: the
relay never decides.

## 1. The seven coherence decisions

### A33: three places where the glossary and the API do not read the same

Evidence: `docs/glossary.md` (rows `condition`, `channel`, `deadline`), `packages/reactor/src/hecate/reactor/condition.lua`.

- **`Condition:signal`.** The glossary row `condition` says "Instead of: event, signal", yet the method that wakes
  waiters is `Condition:signal()` (named after Hoare, 1974). OQ-25 (6) records it and is still open.
  Options: (a) keep `signal` and reword the glossary row: the discouraged word is "signal" for the *concept*, the
  method keeps Hoare's name; (b) rename the method (`notify`, `wake`), a breaking change of an API that is not
  frozen yet, so cheap now and expensive after the freeze. Recommendation: (a), because Hoare's term is the
  academic one, which is what ADR 0004 asks for.
- **`channel`.** The glossary says "Typed communication between coroutines", but a `Channel` carries any Lua value.
  Recommendation: reword to "Communication of values between coroutines" (no API change).
- **`deadline`.** The glossary defines a deadline as an absolute bound and calls a relative duration a "timeout",
  but `reactor.deadline(seconds, fn)` and the option `handshake_deadline` take relative seconds. OQ-22 (answered on
  2026-10-27) confirms relative seconds with `reactor.at` for an absolute instant. Recommendation: state in the
  row that a plain number is a relative duration and that `reactor.at(seconds)` builds the absolute `Instant`.

### A40: `net` has no specification

Evidence: `packages/net/README.md:16` points to `concurrency.md`, whose "Transport" section has twelve lines for
TCP, UDP, pipes and DNS. The buffered layer, the `Stream` interface, TLS (options, errors, trust store,
`handshake_deadline`), the error classes and the cancellation table exist only in the README, in OQ-29, 30, 32, 42,
47 and in ADR 0021 and 0024. `CLAUDE.md` orders the sources of truth ADR, specification, README: for `net` the
README is the specification. The same situation was recorded for `container`, `config` and `log` in Phase 0
(F75, OQ-62); `log` got `logging.md`.

- (a) Write `docs/architecture/networking.md` now, moving the design content out of the README and the OQs.
  Cost: a medium documentation task; benefit: the follow-ups you decided on 2026-10-27 (bind every address,
  CRL option, handshake defaults, `0700` socket directory) then change a specification, not scattered OQ text.
- (b) Record in OQ-62 that the README is the specification until `net` is revised.

Recommendation: (a), as a roadmap item before the gate, done together with the `net` follow-up item, since that
item changes the behaviour the document would describe.

### A41: ADR 0007 is Accepted but still asks for your review

Evidence: `docs/adr/0007-object-model.md`: status "Accepted"; the section "Final spelling (Phase 1
implementation, for owner review and freeze)"; the "Consequences" heading is lost, so three bullets sit under
"Decision". `packages/core/README.md:11` says "API pending owner freeze (ADR 0007)". `docs/adr/README.md` says
an Accepted ADR is immutable.

Decision needed: confirm that the spelling in that section is frozen (CLAUDE.md reserves the freeze of public
APIs to you). If yes, the relay rewrites the heading to "Final spelling (frozen on <date>)", restores
`## Consequences`, and changes the README status. If something is still to change in the `core` API, it must
change before the freeze. Recommendation: freeze `core` now: it is the base of every package, and the ambient
context, errors and `IoError` follow-ups do not touch the spelling of `class`, `trait`, `interface`.

### A42: a test promised by the standards does not exist

Evidence: `coding-standards.md:101-103`, `testing.md:62` and `logging.md:312` promise "a test checks that
documented suspension matches behaviour" and that `---@async` marks the functions observed to yield, measured by
an instrumented run. No such test or task exists (searched `tools/tasks`, `tools/tests`, every package test). Its
absence is why A04 went unnoticed: `fork`, `detach`, `with_ambient` and `ambient` are annotated `---@async` and
never yield.

- (a) Implement it: instrument the scheduler in the test run, record which public functions yielded, compare with
  the annotations. Phase 2 candidate, a small task of its own.
- (b) Mark the sentence "planned" in the three files and fix A04 by hand.

Recommendation: (b) now (the gate stays honest), and (a) as a roadmap item in Phase 2 before `http`, whose
public API will multiply suspending functions. It pairs naturally with C03 below.

### C03: `check-annotations` is marked P1 and does not exist

Evidence: `docs/architecture/automation.md:37-38` lists the task (every exported symbol annotated; suspending
functions carry `@async`; functions returning `nil` for absence declare a nullable return, ADR 0018);
ADR 0018:50 relies on it; `lua tools/run.lua --list` has no such task; no roadmap item delivers it. The
definition of done ("public API annotated") therefore has no automated gate, and `lint` only checks that a chunk
compiles and declares no globals.

- (a) Add a roadmap item before the gate: a first version (exported symbols annotated, nullable returns). It
  needs `lua-language-server` or a Lua-side scan, to be chosen.
- (b) Move it to a named later phase (for example Phase 3 with `test`, or Phase 7, the quality pass) and drop "P1"
  from the table.

Recommendation: (a) for the annotation-presence and nullable-return checks, since Phase 2 adds many public APIs;
the `@async` check joins it with A42.

### C17: four decided and implemented entries still sit in the open table

Evidence in `docs/open-questions.md`: OQ-33 (`doc` file system: you accepted a dependency on `reactor` and `json`
on 2026-10-13; implemented over `reactor.fs`, and `json` replaced the in-house encoder, yet the text still says
`hecate.json` "has no source yet"); OQ-35 (`doc` conventions, point (6) superseded by ADR 0022, point (12)
`source_revision` is "read by nothing yet" while the French pages now carry it); OQ-36 (search and highlighting:
your decisions were recorded, search went to Pagefind by OQ-39); OQ-40 (code reference: point (1) is obsolete
since `hecate.json` exists).

Decision needed: for each, either confirm "resolved" (the relay moves it to the Resolved table with a link to the
implementation) or name the sub-point that stays open (for example OQ-35 (12), whether `source_revision` becomes
a CI check, and OQ-38 for user projects). Recommendation: resolve all four and open one small entry for the
French `source_revision` stamps (12 of 16 pages are behind the English source, content in step).

### C18: five `reactor`/`net` entries are in no gate list

OQ-25, 29, 30, 32 and 42 are "implemented conservatively" entries of `reactor` and `net`, all `decision`, none
listed among the questions to put to you at the Phase 1 gate. They hold choices you have not confirmed, for
example: `select` picks the first ready item in argument order (25 (2)); `Monitor` follows Mesa semantics (25
(3)); a record longer than `limit` raises `core.ProtocolError` (29 (3)); `connect` tries addresses one after the
other without Happy Eyeballs (32 (2)); `send_to` takes a numeric address only (42 (1)); cancelling a write closes
the stream (30 (2)).

Decision needed: either put them to you now (the relay lists each sub-point, as was done for OQ-47), or record a
deferral to the Phase 2 gate. Recommendation: confirm them in one pass with the OQ-47 follow-up, because the
`net` follow-up item will touch 32 (3) (bind every address) and 29 (5) (writer close, after `shield`).

## 2. The six open questions of the gate

Six were put to you; you answered them on 2026-10-27 and the answers are recorded in
`docs/open-questions.md`. Two points are still open.

### OQ-50: how does a PATCH tell "unchanged" from "cleared"?

Context (typed route content, `schema` and `kernel`, Phase 2). You decided: the schema is tied to the class; the
route names the schema; the validator takes the HTTP method into account; an absent attribute is nil for POST and
PUT, and validation fails only when the class attribute is not nilable. For a PATCH, an absent attribute means
"unchanged" and an explicit `null` means "clear" (it fails if the attribute is not nilable). Lua cannot store the
difference in a plain table: absent and `null` are both `nil`.

- (a) The instance carries a presence set, read with `schema.sent(instance, name)`. Plain instances, no sentinel
  in user code; one extra table per PATCH instance.
- (b) The attribute holds `json.null` for "clear". No extra table, but `json` leaks into user classes (`json` is
  layer 1 and is meant to stay unaware of classes), and every use of the attribute must test for the sentinel.

Recommendation: (a). It keeps the class model clean and the cost is paid only by PATCH. To confirm; the detail is
settled when `schema` is specified.

### OQ-26 (4): all libuv I/O needs the real clock

A reactor with the virtual clock (used by tests to make time deterministic) refuses real I/O. The proposal is to
keep refusing: a real-time idle threshold that advances the virtual clock when nothing is runnable (Trio's
`autojump_threshold`) is not deterministic, which defeats the purpose of the virtual clock. Tests that need both
time control and I/O should use in-memory streams (the in-process client of `test`). Recommendation: keep
refusing, and make the error message name that alternative.

### Recorded answers (for the file)

OQ-22 confirmed and deferred (wall-clock type); OQ-23 `reactor.shield(fn)` with its own deadline before `kernel`;
OQ-24 strict, supervised work later as an explicit scope; OQ-26 (1) `on_unobserved_failure` hook, (2)
`core.IoError` as a base class of `reactor.IoError`, (3) and (5) confirmed; OQ-47 (1) to (8) answered, with the
follow-ups now on the roadmap (two items before the Phase 1 gate).

## 3. Ambient context in the glossary (A29)

Added, in `docs/glossary.md`, the website glossary and the French terms: `ambient context`, `ambient binding`,
`ambient key`, `logger context`, `bound log fields` and `request context` (planned). I read "all the context
scopes" as the places where context lives or flows today (the reactor's ambient bindings, the logger's own
context, the fields of `log.bind`) plus the request context that `kernel`, `security` and deadlines will bind
(ADR 0025). If you meant a different list, for example a closed list of ambient keys, say so: the glossary rows
are cheap to change.
