# Phase 1 gate: coherence findings

Audit of the "Coherence" check of `docs/roadmap.md` ("Phase gates", item 3), method of
[phase-0-coherence-findings.md](phase-0-coherence-findings.md). Three raw parts follow (A: `core`, `reactor`,
`net`; B: `json`, `log`, `doc`, benchmarks, tools; C: cross-cutting: CI, layering, open questions, roadmap,
status statements, website). 104 findings: 4 D, the others S or M.

## Status after the fixing passes (branch `claude/relay-phase-1-gate`)

Every **S** finding was fixed in this pull request, except those below. Finding rows keep their original text:
they describe the state before the fix.

Left for the owner (**D**):

- A29, A33, A40, A41, A42 (part A, owner items).
- C03 and B29 (`check-annotations` is marked P1 and does not exist: add a roadmap item or move it to a named phase).
- C17 (open-questions entries decided and implemented: OQ-31, 33, 34, 35, 36, 40), C18 (OQ-25, 29, 30, 32, 42 await
  confirmation and are in no gate list).
- The `ambient context` glossary entry, where the baselines of benchmarks live (C-notes).

Left undone (not blocking, **S/M**): A02 (about 30 `core` error messages without the qualified prefix: convert, or record
the exception in coding-standards.md), A44 and B32 (French `source_revision`: five pages bumped after comparison, the
others to be compared page by page), C21 (merge the two "Phase 2" roadmap headings), C22 (`doc` catalogued as Phase 3
although its minimal slice is Phase 1; the README status explains it).

## Phase 1 gate, coherence audit, part A: `core`, `reactor`, `net`

Scope: the "Coherence" check of `docs/roadmap.md` ("Phase gates", item 3), for the packages `core`,
`reactor` and `net` and everything that speaks about them. Method and format follow
`docs/reviews/phase-0-coherence-findings.md`. Reference vocabulary: `docs/glossary.md`, ADR 0004.
Branch `claude/relay-phase-1-gate`, Linux. Nothing was fixed, nothing committed.

### What was read, and how

Read in full, line by line:

- `packages/core`: `README.md`, `CLAUDE.md`, the rockspec, the example, the benchmark, and every file of
  `src/hecate/core/` (`init`, `class`, `trait`, `interface`, `introspection`, `enumeration`,
  `value_class`, `error`, `compat`, `internal/raise`, `internal/registry`).
- `packages/reactor`: `README.md`, `CLAUDE.md`, the rockspec, and every file of `src/hecate/reactor/`
  (`init`, `instant`, `future`, `scope`, `reactor`, `primitives`, `channel`, `channel_operation`,
  `semaphore`, `mutex`, `monitor`, `condition`, `permit`, `signal`, `tcp`, `pipe`, `udp`, `dns`, `fs`,
  `process`, `ipc`, `internal/*`).
- `packages/net`: `README.md`, `CLAUDE.md`, the rockspec, and `src/hecate/net/` apart from two files
  (`init`, `errors`, `stream`, `tcp`, `dns`, `tcp_stream`, `tcp_listener`, `udp`, `udp_socket`, `pipe`,
  `pipe_stream`, `pipe_listener`, `buffered_reader`, `buffered_writer`, `tls`).
- `docs/architecture/concurrency.md`, `docs/architecture/object-model.md`, `docs/glossary.md`,
  `docs/adr/README.md`, ADR 0004, 0007, 0024, 0025, `docs/reviews/phase-0-coherence-findings.md`.
- Website, English: `index.md`, `reference/index.md`, `explanation/index.md`,
  `explanation/transport-model.md`, `explanation/multi-process-serving.md`,
  `explanation/tls-trust-and-security.md`, `how-to/index.md`, `how-to/connect-and-serve-over-tcp.md`,
  `how-to/deadlines-and-cancellation.md`, `how-to/udp-pipes-and-dns.md`,
  `how-to/run-processes-and-pass-connections.md`; `website/CLAUDE.md`; `website/fr/glossary-terms.md`.
- `llms.txt` (head), the Phase 1 and Phase 2 sections of `docs/roadmap.md`, the "Phase gates" section.

Read in part, or by search only:

- `packages/net/src/hecate/net/tls_stream.lua` (signatures, annotations and messages by search), the
  Rust native module (search for `unsafe`, versions, early data), all tests (test names, selected
  excerpts: `core` class tests, `reactor` ambient and io tests, `net` api test and error-message
  assertions), the example files (names and a few bodies).
- ADR 0002, 0003, 0021, 0023 (0023: the decision items 2 to 5; the others by search).
- `docs/open-questions.md` (about 96 lines, but very long rows): read in full the rows OQ-8, 22 to 26,
  29, 31, 42, 43, 47 and the OQ-55/56/63 prose; OQ-30 and OQ-32 only up to about 1 500 characters; OQ-19,
  20, 27, 28, 41 not read; the rest by search.
- `website/en/how-to/tls-client-and-server.md` (the head, the reasons table and a keyword search),
  `how-to/encode-and-decode-json.md`, `log-structured-records.md`, `measure-performance.md` (not read,
  out of scope).
- The French pages: not read line by line. Compared mechanically with the English ones: number of
  headings, code fences and paragraph blocks, every number (after normalising French separators),
  `source_revision` against the git history; `website/fr/glossary-terms.md` and the French reference
  index and home page read in full; the French glossary compared by row count and by search.
- `CHANGELOG.md`, `docs/architecture/logging.md`, `docs/architecture/overview.md`,
  `docs/developer-experience.md`, `docs/architecture/testing.md`, `coding-standards.md` ("Errors" and
  "Documentation in code"): by search and targeted reading.

Mechanical checks run: `check-glossary` (ok), `check-docs-examples` (ok), `test core`, `test reactor`,
`test net` (all ok); deny-list search (`promise`, `middleware`, `DTO`, `nursery`, `fiber`, `race`, `await`,
`gather`, `event loop`, `cluster mode`, `service locator`, `task group`, `green thread`) and
context-dependent terms (`task`, `handler`, `timeout`, `callback`, `thread`) over the three packages, the
website and the two specifications; British-spelling search (no American spelling found); search for the
names removed by the renames of Phase 0 and of ADR 0025 (`tcp_connect`, `udp_bind`, `pipe_listen`,
`live_tasks`, `hecate.class`, `reactor.local`, `with_local`, `message channel`, `control channel`): none left
outside the changelog and the spikes.

Not run: `typecheck` and the strict website build (no `lua-language-server` in this environment), so the
generated reference of `core`, `reactor` and `net` (not committed) was not inspected. Everything below about
the reference is deduced from the annotations.

Severity: **U** user-facing (public API, doc comments that feed the reference, README Public API, website),
**I** internal. Fix size: **S** a few lines, **M** several files or a mechanical sweep, **D** needs an owner
decision first.

### Summary

45 findings: 21 U, 24 I. By size: 40 S, 1 M, 4 D. No glossary deny-list term is used as an identifier or in
prose of the three packages (the only hits are the word "race" in three test comments, A37). British spelling
is applied everywhere checked. The numeric defaults checked (backlog 128, keep-alive delay 60, `nodelay`
true, read-ahead 64 KiB, `limit` 65536, writer capacity 8192, `max_message` 16 MiB, `handshake_deadline` 10,
socket path 107/103 bytes, pipe name 256, thread pool 4) agree between code, README, specification and the
English and French website. The English and French website pages are structurally in step (same headings,
code blocks, paragraphs and numbers).

The five findings that matter most: A01, A02, A04, A05, A07.

### Findings

#### 1. Behaviour and messages that contradict the stated rule

| ID | Sev | Size | Where | Quoted text | What is wrong | Proposed fix |
|---|---|---|---|---|---|---|
| A01 | U | S | `packages/reactor/src/hecate/reactor/fs.lua:28,29,33,39,49,53,57,63,72,75,88,96,104,113`; rule at `docs/architecture/coding-standards.md:75-78`; doc at `internal/uv_call.lua:21` | `require_path("reactor.read_file", path)`; `uv_call.request("reactor.read_file", "open " .. path, ...)`; `uv_call.lua:21`: "`qualified` is the call as the caller wrote it (`reactor.fs.read_file`, `net.TcpStream.read`; ...)" | The message prefix of every `reactor.fs` function names a function that does not exist (`reactor.read_file`, `reactor.stat`, `reactor.list`...): the caller wrote `reactor.fs.read_file`. The rule says "exactly as the caller wrote the call"; `uv_call.lua:21` itself gives `reactor.fs.read_file` as the example; the changelog (`CHANGELOG.md:101`) says every failure of the two packages follows the rule. No test asserts the message (`tests/unit/io_test.lua:41-46` checks class and `errno` only). | Use `reactor.fs.<function>` in the 14 places (messages and `context.operation` prefixes keep their stable names); add one test of a message prefix. |
| A02 | U | S | `packages/core/src/hecate/core/class.lua:79,82,87,93,152`; `trait.lua:45,112,113,119`; `interface.lua:36,37,47,53`; `enumeration.lua:46,49,54,58,62`; `introspection.lua:51,80,91,109,123,152,179`; `value_class.lua:95` | "class name must be a non-empty string, got ..."; "finalise expects a class created with core.class"; "is_finalised expects a class"; "trait name must be a string, got ..."; "enumeration name must be a non-empty string, got ..." | `core` raises about 30 `ArgumentError` messages with no `module.function:` prefix. `coding-standards.md:75-77`: "A message that is raised for a call starts with the qualified `module.function:` exactly as the caller wrote the call"; `CHANGELOG.md:102` lists `hecate.core` among the packages converted ("Messages of `ArgumentError` ... now start with the qualified `module.function:`"). Only `reactor`, `net`, `json`, `log` were converted. | Prefix with `core.class:`, `core.finalise:`, `core.trait:` ... (the `raise` helper can take the call name), update `core` tests, or state the exception in `coding-standards.md`. |
| A03 | U | S | `packages/net/src/hecate/net/tls.lua:438`, `net/tcp.lua:331,333,342,349,371,374` | `local stream = tcp.connect(host, port, transport)` (called by `net.connect_tls`); `split_options("net.connect", ...)`, `dns.resolve_for("net.connect", ...)` | A name that does not resolve, or a TCP failure, raised through `net.connect_tls` reads `net.connect: connect to host:443 failed: ...` while the caller wrote `net.connect_tls`. Same rule as A02; `CHANGELOG.md:101` claims the rule holds for `net`. (An option of `connect_tls` is checked earlier under the right name, so only I/O failures are affected.) | Give `tcp.connect` an internal `call` parameter (as `dns.resolve_for` already has) and pass `"net.connect_tls"`; add a test. |
| A04 | U | S | `packages/reactor/src/hecate/reactor/primitives.lua:107,126,151,177` (`---@async` on `fork`, `detach`, `with_ambient`, `ambient`); `packages/reactor/README.md:58`; `docs/architecture/concurrency.md:75` | README: "`reactor.detach(fn, ...)` \| *suspends*. Starts `fn` in the application scope"; spec: "which calls may suspend: **every I/O operation, every primitive above, and nothing else**"; `coding-standards.md:100`: "`---@async` is mandatory on every function that can suspend" | `fork`, `detach`, `ambient` never yield (they create a computation or read a table; `with_ambient` suspends only if `fn` does). Yet they are annotated `---@async` (the reference shows "May suspend"), the README says `detach` *suspends* while it does not say so for `fork`, and the specification says every primitive suspends. What they really share is that they raise `NonYieldableContextError` outside a managed coroutine. | Drop `---@async` on these four (or define "async" as "needs a managed coroutine" everywhere and say so); README: remove "*suspends*" from `detach`; concurrency.md:75 and glossary row "suspension point": restate ("every I/O operation and `join`, `select`, `sleep`, `scope`, `deadline`, the channel and lock operations; `fork`, `detach`, `with_ambient` and `ambient` only require a managed coroutine"). |
| A05 | U | S | `packages/net/src/hecate/net/tcp_stream.lua:81`; `packages/reactor/src/hecate/reactor/tcp.lua:369`; `packages/reactor/src/hecate/reactor/udp.lua:70` | `---@param delay? number` (net); reactor `tcp.lua:369`: `---@param delay? integer a positive integer, default 60`; `udp.lua:70`: `---@param port integer  UDP port, 1..65535` for `UdpSocket:send_to`, while `check_endpoint` (udp.lua:234-241) accepts 0..65535 | Two annotations disagree with the code or with each other: `net.TcpStream:set_keepalive` declares `number`, the reactor method it forwards to and the code require a positive integer; `reactor.UdpSocket:send_to` documents ports 1..65535 but accepts 0 (only the `net` wrapper, `udp_socket.lua:238`, refuses 0). | `---@param delay? integer`; for the reactor, either refuse port 0 in `send_to` or document 0..65535. |

#### 2. Statements that are stale or untrue

| ID | Sev | Size | Where | Quoted text | What is wrong | Proposed fix |
|---|---|---|---|---|---|---|
| A06 | U | S | `packages/reactor/README.md:44` | "Implemented (steps 1 to 4, then TCP transport)." | Stale: UDP, pipes, resolution, processes, `ipc`, `reuseport`, ambient context are all implemented and listed in the same README. "Steps" refer to a roadmap item that is closed. | "Implemented." |
| A07 | U | S | `packages/reactor/README.md:27` | "timers, signals, child processes, pipes, file-system operations and TCP transport (connect, listen, accept, read, write, shutdown) as suspending calls; TCP, UDP (`bind_udp`) and pipes (`connect_pipe`, `listen_pipe`) transport, and name resolution (`resolve`), all as suspending calls" | The responsibility bullet says TCP and pipes twice (two sentences glued together) and says all of them are suspending calls, which is untrue of `listen_tcp`, `bind_udp`, `listen_pipe` (they do not suspend, README:68, concurrency.md). | One sentence: "timers, signals, child processes, file-system operations, TCP, UDP and pipe transport and name resolution (the calls that wait are suspending calls)". |
| A08 | U | S | `packages/reactor/src/hecate/reactor/init.lua:1-3` | "Step 1 of the roadmap item: loop, Future, fork, join, select, sleep, scope, deadline, cancellation and virtual clock." | The header of the public entry point describes a past milestone; the module now exports channels, primitives, transport, processes, `ipc`, ambient context. | Replace by a one-line description of the module. |
| A09 | I | S | `docs/architecture/concurrency.md:3`, `docs/architecture/object-model.md:3` and `:27` | concurrency.md: "Status: specification"; object-model.md: "## Proposed surface (illustrative)" | Both are implemented (Phase 1 ticked). The object-model section heading says "Proposed ... illustrative" for code that is the real, tested surface (and `:63` says the spelling "was settled"). `concurrency.md:34` correctly still marks `offload` as not implemented, which a "Status" line should reflect ("implemented, except `offload`"). | "Status: implemented in Phase 1 (`offload`: Phase 2)"; rename the heading "Declaration spelling". |
| A10 | I | S | `docs/architecture/object-model.md:10` | "1. Classes with single inheritance, constructors and `super` calls." | There is no `super` in `core` (no keyword, no function: `grep super packages/core/src` finds only `superclass`). ADR 0007:34 says "super call: `core.superclass(C).init(self, ...)`", and `class_test.lua:50` tests that idiom. | "...constructors (`init`) and calls to the superclass (`core.superclass(C).init(self, ...)`)". |
| A11 | I | S | `docs/architecture/object-model.md:90-93` | "`DeadlineExceededError`, `NetworkError`, `ProtocolError`, `ValidationError`, `DatabaseError` (with SQLSTATE when available), etc." | The list omits `NonYieldableContextError` and `ClosedChannelError`, which exist in `core` (`core/error.lua:119,122`), are in the README and are the two errors the reactor raises most. | Add both (and `ConformanceError` is there). |
| A12 | I | S | `docs/architecture/concurrency.md:137-138` | "carries `ready`, `stop(deadline)` and `reload`" | ADR 0023:109 and `website/en/explanation/multi-process-serving.md:230`: "`ready`, `stop(deadline)`, `reload` and counters". | Add "counters" (or drop it from ADR and website). |
| A13 | I | S | `docs/architecture/concurrency.md:21-34` | the "Primitives" table | The table omits `detach` (named only in rule 2), `now`/`at` and `Instant`, `wait_signal`, `run_process`, `spawn`, `fs`, `resolve`, `Scope`, `Permit`, which the README lists and the specification names elsewhere (section "Transport", "Workers"). The README has become the only complete list, but precedence puts the specification first (CLAUDE.md). | Add the rows or say "the complete list is in the package README". |
| A14 | I | S | `docs/adr/0025-ambient-context.md:8` | "**Related:** [concurrency.md](../architecture/concurrency.md) ("Scopes"), OQ-55, ADR 0002" | `concurrency.md` has no section "Scopes" (the sections are "Structured concurrency" and "Ambient context"). OQ-55 itself no longer exists as an entry (see A15). | Cite "Ambient context". |
| A15 | I | S | `docs/open-questions.md:81-86` (and `:54`, `:96`) | "### OQ-55 addendum — asynchronous sinks (corrected)"; OQ-8 row: "Remaining: the `reactor` primitives (roadmap, Phase 2) and OQ-43"; the last line, the row starting `OQ-63` | (1) An "addendum" to OQ-55, but no OQ-55 entry exists in the file; ADR 0025 and the roadmap (`:124`) still cite OQ-55. (2) The OQ-8 row says the `reactor` primitives remain to do; they are implemented (roadmap "Phase 2 additional spike", `[x]`; `reactor/README.md:11`). (3) The OQ-63 row sits after the OQ-56 prose, outside any table (the Phase 0 finding F37 again). | Write a short resolved entry OQ-55 in the "Resolved" table; "Remaining: OQ-43 only"; move the OQ-63 row into the Resolved table. |
| A16 | I | S | `docs/open-questions.md` OQ-32 (5) | "`net.TcpStream` and `TcpListener` wrap the reactor objects and let the error propagate unchanged" | Since the qualified-prefix change, `net` renames the call in the message (`errors.rename`, `_label`), so the error does not propagate unchanged (class and context do; the message does not). | "propagate with the call renamed". |
| A17 | I | S | `docs/roadmap.md:95` and `:85-87` | "the French translation of those pages (13 pages; terminology in `website/fr/glossary-terms.md`)" | `website/fr` now holds 16 pages (index, 4 explanation, 9 how-to, 2 reference), as does `website/en`. Also `packages/reactor/README.md:10` says "Roadmap phase 1" while the roadmap ticks `spawn`, `ipc` and `reuseport` under "Phase 2 — additional spike". | Update the count or drop it; state in the README "1 (transport primitives of ADR 0023: phase 2)". |
| A18 | I | S | `CHANGELOG.md:57,62,68,69,73,91` | ":57 a framed message channel between parent and child ... the `reuseport` option of `tcp_listen`"; ":62 Proposed [ADR 0023]"; ":68 `pipe_connect`, `pipe_listen`"; ":69 `udp_bind`"; ":73 `tcp_connect`, `tcp_listen`"; ":91 `pipe_listen` option `mode`" | The `[Unreleased]` section is one list for a never-released version; its entries use the names removed by the verb-first rename (`CHANGELOG.md:102`), the discouraged "message channel" (glossary: "message pipe ... Instead of: channel"), and call ADR 0023 "Proposed" (Accepted, `docs/adr/README.md`). A reader of the changelog cannot tell which names exist. | Rewrite the six entries with the current names (history stays in git), or fold the section. |
| A19 | U | S | `website/en/reference/index.md:12-20` (and `website/fr/reference/index.md:13-20`) | "One section exists per documented package." followed by `core`, `reactor`, `net`, `json` | `DEFAULT_PACKAGES = { "core", "reactor", "net", "json", "log" }` (`packages/doc/src/hecate/doc/reference_site.lua:16`) and `website/en/index.md:17` ("core, reactor, net, json and log packages are implemented and documented") include `log`; the reference index omits `hecate.log`. | Add the `hecate.log` line in both languages. |
| A20 | I | S | `packages/core/README.md:86` | "tests/unit/  tests/integration/  tests/fixtures/" | `packages/core/tests` holds only `unit/` (and `.gitkeep`): no `integration`, no `fixtures`. | List `tests/unit/` only. |

#### 3. The README "Public API" tables against the code

| ID | Sev | Size | Where | Quoted text | What is wrong | Proposed fix |
|---|---|---|---|---|---|---|
| A21 | U | M | `packages/reactor/README.md:47-78` (no row) ; code `udp.lua:269-410`, `init.lua:78` | the table has rows for TCP (67-70) and pipes (71) but none for UDP | `reactor.bind_udp(host, port)` and `UdpSocket` (`send_to(host, port, data)`, `receive_from()`, `local_address()`, `close()`, `is_closed()`, `<close>`) are public, tested, in the reference, in concurrency.md "Transport", and cited in the README only in a bullet and in the status cell. The Public API table, which says it is the API, lacks them. | Add the row(s), including the cancellation rule (a cancelled `send_to` closes, `receive_from` does not) and the "one coroutine receives at a time" rule. |
| A22 | U | S | `packages/reactor/README.md:47-78` ; code `init.lua:114-117`, `reactor.lua:213-225`, `monitor.lua:386-388`, `channel.lua:129-138`, `scope.lua:280-289` | (no mention) | Public names missing from the README table: `reactor.is_future(value)` (exported, annotated, **no test and no document anywhere**), `reactor.IoError` and `reactor.TransportError` as exported fields (only used in prose), `Reactor:is_real()`, `Reactor.open_handles()` (used by tests and the `leaks` task), `Monitor:is_entered()`, the boolean returned by `Channel:close()` (OQ-25 (1) documents it; README does not), the optional error argument of `Scope:cancel(err?)` (README: `:cancel()`), `Instant` as a class. | Add them to the table, add a test for `reactor.is_future`, or make `is_future` private. |
| A23 | U | S | `packages/net/README.md:113-115`, `:49-51`; code `tls.lua:235,296,326`, `buffered_reader.lua:209,251` | "`net.tls.accept(stream, config)`", "`net.tls.connect(stream, server_name, config)`", "`net.tls.client_config(options)`", "`reader:read_line(limit)`", "`reader:read_until(delimiter, limit)`", "`reader:read_some(max)`" | The signatures in the README differ from the code: `tls.connect` and `tls.accept` take a fourth/third optional argument `options` (`handshake_deadline`, `hecate.net.TlsHandshakeOptions`) that the table never shows (it is only mentioned in the `connect_tls` row and in a sentence about the accept loop); `client_config(options?)` is optional; `limit` and `max` are optional in `read_line`, `read_until`, `read_some`. | Show `options?` and the optional marks; give `handshake_deadline` a mention in the `tls.accept` and `tls.connect` rows. |
| A24 | U | S | `packages/net/README.md:67` | "A failure reads `listen on 0.0.0.0:8080 failed: EADDRINUSE address already in use`"; row `net.connect`: "it raises a `reactor.TransportError` such as `connect to example.org:5432 failed: ECONNREFUSED connection refused (tried 10.0.0.1, 10.0.0.2)`" | The real messages start with the qualified call (`net.connect: connect to ... failed: ...`, `tcp_test.lua:300`, `:622`), as the changelog and coding-standards say. The README quotes the message without its prefix. | Quote the full message. |
| A25 | U | S | `packages/reactor/README.md:70` and `tcp.lua:408-412` | "a connection whose peer already reset it (`EINVAL`, `ENOTCONN`, `ECONNRESET` while applying the options ...) is closed and skipped" | The code also skips `ECONNABORTED` (`DROPPED`, `tcp.lua:406`), which neither the README, nor the doc comment of `accept`, nor the OQ lists. | Add `ECONNABORTED` to the three places. |
| A26 | U | S | `packages/reactor/src/hecate/reactor/tcp.lua:341`, `:348` | "--- Address of the remote end." | The Phase 0 finding F48 corrected this wording in `net/tcp_stream.lua` ("Address of the peer") but `reactor.TcpStream:peer_address` (another file, excluded from that pass) still says "remote end"; the glossary row "peer" says "remote ... instead of". | "Address of the peer." |
| A27 | U | S | `packages/net/src/hecate/net/tcp_stream.lua:64`, `tcp_listener.lua:131`, `pipe_stream.lua:50`, `pipe_listener.lua:36`, `udp_socket.lua:79` (and `is_closed` of `BufferedReader`, `BufferedWriter`) | `---@return boolean` with no description line | `coding-standards.md:101`: "First line of a doc comment: one sentence in the indicative mood". Seven public methods have no summary sentence, so their reference entries have an empty summary. Other `is_closed` (reactor classes, `UdpSocket` in reactor) have it. | Add "Returns whether the stream is closed." |
| A28 | U | S | `packages/reactor/src/hecate/reactor/tcp.lua` (class `TcpStream` options) and README | `---@overload fun(handle: table, options?: table)` | The documented exported class constructors (`reactor.TcpStream`, `Process`, `Peer`, `PipeStream`...) are `@private` `init`s meant for internal use but exported "as their class"; the README lists `TcpStream`, `TcpListener`, `Future`, `Scope` as "Names", suggesting they are constructible by users (`reactor.TcpStream(handle)`). Only `reactor.Peer(handle, options)` is documented as a constructor. | State in the README which classes are only returned by calls, not constructed by users. |

#### 4. Terminology and vocabulary

| ID | Sev | Size | Where | Quoted text | What is wrong | Proposed fix |
|---|---|---|---|---|---|---|
| A29 | U | S | `docs/glossary.md` (no entry), `website/en/reference/glossary.md`, `website/fr/glossary-terms.md` | (absence) | "ambient context" (ADR 0025, `concurrency.md:52`, `reactor.with_ambient`, `reactor.ambient`, `log.bind`, `log` specification) is the central concept of a public API and is absent from the glossary, the public glossary, and the French decisions. ADR 0004: "New terms are added to the glossary in the same pull request that introduces them". Phase 0 resolved F02 as "not a finding", but that concerned the `log` wording, not the missing entry. Also: no website page (English or French) describes `with_ambient`; only the generated reference will. | Add the row ("Immutable key-value bindings visible in a computation and in the computations it forks or detaches", ADR 0025, instead of thread-local, task-local) and « contexte ambiant »; owner to confirm given the Phase 0 outcome. |
| A30 | I | S | `packages/reactor/src/hecate/reactor/reactor.lua:2` | "every unit of work is a coroutine ("coroutine")" | "unit of work" is Fowler's change-tracking object (glossary, Data) and the Phase 0 finding F01 removed it from `concurrency.md`; this header comment still uses it (and the quotation marks around the word coroutine make no sense). | "every computation is a coroutine resumed by the scheduler only". |
| A31 | I | S | `packages/reactor/src/hecate/reactor/permit.lua:4`, `tcp.lua:5`, `reactor.lua:257-259`, `reactor.lua:398`; `packages/net/src/hecate/net/buffered_writer.lua:124` | "(reactor/CLAUDE.md invariant: cancellation runs `<close>` handlers)"; "a `<close>` handler must not suspend" | The Phase 0 finding F74 reserved "handler" for I/O completion handlers and rewrote the `reactor/CLAUDE.md` invariant to "cancellation runs the `__close` metamethods of pending `<close>` variables". Four code comments still quote the old invariant verbatim, so the quotation no longer matches its source. | Quote the current wording ("`__close` metamethods"). |
| A32 | I | S | `packages/reactor/src/hecate/reactor/reactor.lua:185` | "--- Returns the coroutine of the running coroutine, or raises `NonYieldableContextError`." | It returns the internal computation record. | "Returns the computation record of the running coroutine ...". |
| A33 | I | D | `docs/glossary.md:48`, `:44`, `:31`; `packages/reactor/src/hecate/reactor/condition.lua` (`Condition:signal`) | glossary condition row: "Instead of: event, signal"; channel: "Typed communication between coroutines"; deadline: "Absolute bound" | (a) The API names the wake-up `Condition:signal()` although the glossary lists "signal" as discouraged (OQ-25 (6), still open as a decision). (b) `Channel` carries any Lua value, not a typed one. (c) `reactor.deadline(seconds, fn)` and the option `handshake_deadline` take a relative duration, which the glossary calls a "timeout"; the row only says "both may be accepted". Documented, but three places where the glossary and the API do not read the same. | Owner decision on OQ-25 (6); reword the channel row; state in the deadline row that a plain number is a relative duration (OQ-22). |
| A34 | I | S | `docs/adr/0004-academic-vocabulary.md` ("Verification"), `tools/lib/glossary.lua:7-20` | ADR: "a deny-list of discouraged identifiers (`promise`, `spawn`, `middleware`, `race`, ...)" | `race` is not in `M.denied` (and neither are `await`, `gather`, `DTO`, `event loop`, `cluster mode`, which the Phase 0 audit searched by hand); the comment of the tool says it is "restricted to terms never acceptable in identifiers". The ADR names a term the tool does not check. | Edit the ADR sentence ("... `promise`, `spawn`, `middleware`, ... see `tools/lib/glossary.lua`"). |
| A35 | I | S | `packages/reactor/tests/integration/tcp_test.lua:271`, `packages/net/tests/integration/tcp_test.lua:388`, `:678` | "the read won the race"; "that race visible"; "the connect won the race" | "race" is a deny-list term (instead of `select`); in these comments it means the concurrency hazard, a legitimate English use, but the Phase 0 audit recorded the deny-list as clean outside the glossary. | Leave, or write "ran first". |
| A36 | I | S | `docs/architecture/concurrency.md:46-48` | "`<close>` variables and `finally`-style cleanup run normally." | Lua has no `finally`; the sentence borrows another ecosystem's construct (OQ-23 also says "`finally`-style block"). Also: the rule says cancellation is "delivered ... at the next suspension point", but the implementation (and the README, OQ-23) is level-triggered: every later suspension point raises again, which the specification does not say. | "cleanup in `<close>` variables runs normally"; add "and at every later suspension point of the cancelled scope (OQ-23)". |
| A37 | U | S | `website/fr/how-to/log-structured-records.md:36` | "Les sévérités sont les huit de la RFC 5424" | `website/fr/glossary-terms.md:59`: "severity \| gravité ... jamais « niveau » ni « sévérité »". (Outside the three packages; found while comparing the French pages.) | « Les gravités sont les huit de la RFC 5424 ». |

#### 5. Documents that do not say the same thing about the packages

| ID | Sev | Size | Where | Quoted text | What is wrong | Proposed fix |
|---|---|---|---|---|---|---|
| A38 | I | S | `packages/reactor/README.md:17` and `CLAUDE.md:13`; `packages/net/README.md:17` and `CLAUDE.md:13-14`; `packages/core/README.md:17` | reactor "Decisions": ADR 0002, 0003, 0004; net "Decisions": ADR 0002, 0003, 0021; core: ADR 0001, 0004, 0007 | The decisions that the same README cites are missing from its own "Decisions" row: reactor cites ADR 0023 (spawn, `ipc`, `reuseport`: README:11, 62-65) and ADR 0025 (ambient context: README:59) without listing them; net cites ADR 0024 (status cell and TLS section) and lists neither it nor OQ-28...; core's error hierarchy is ADR 0018 (`core/init.lua:2`, `error.lua:1`). The `CLAUDE.md` "Read before changing anything" lists have the same gaps, so an agent working on `spawn` is not told to read ADR 0023. | Add the ADRs to the three READMEs and the three `CLAUDE.md`. |
| A39 | U | S | `packages/README.md:15`, `packages/reactor/README.md:3`, `hecate-reactor-scm-1.rockspec:10`, `llms.txt:56` | "The reactor over libuv (luv): coroutine scheduler, futures, structured concurrency, synchronisation primitives, timers, signals, processes, file system." | The one-line summary (generated into the catalogue, the rockspec and `llms.txt`) omits what is now half of the package: the TCP, UDP and pipe transport and name resolution (`concurrency.md` "Transport", ADR 0002 "luv is wrapped once, here"), and the ambient context. The website reference index (`reference/index.md:14-15`) does list them. | Add "network transport (TCP, UDP, pipes, name resolution), ambient context" to the summary and run the generators. |
| A40 | I | D | `docs/architecture/` (no file); `packages/net/README.md:16` | "Specification \| [concurrency.md](../../docs/architecture/concurrency.md)" | `net` has no specification: concurrency.md "Transport" has twelve lines for TCP, UDP, pipes and DNS; the buffered layer, the `Stream` interface, TLS (options, errors, trust, `handshake_deadline`), the error classes and the cancellation table exist only in the README, the OQs (29, 30, 32, 42, 47) and ADR 0021/0024. CLAUDE.md orders sources of truth ADR, specification, README: here the README is the specification. (The same situation was recorded for `container`, `config`, `log` in Phase 0, F75/OQ-62; `log` got `logging.md`.) | Owner decision: write `docs/architecture/networking.md` (move the design content out of the README and the OQs), or record the README as the specification in OQ-62. |
| A41 | I | D | `docs/adr/0007-object-model.md:3`, `:29`, `:62-64`; `packages/core/README.md:11` | Status "Accepted"; "### Final spelling (Phase 1 implementation, for owner review and freeze)"; three orphaned bullets "- One mental model across framework and applications." | An Accepted ADR (`docs/adr/README.md`: "immutable once Accepted") that still asks for owner review of its own spelling; the README says "API pending owner freeze (ADR 0007)". The ADR also lost its "Consequences" heading: the last bullets sit under "Decision" after a paragraph about traits. | Owner: confirm the freeze and rewrite the heading ("Final spelling (frozen ...)"); restore "## Consequences". |
| A42 | I | D | `docs/architecture/coding-standards.md:101-103`, `docs/architecture/testing.md:62`, `docs/architecture/logging.md:312` | "A test checks that documented suspension matches behaviour (see testing.md)."; "functions annotated `---@async` are the ones observed to yield, measured by an instrumented run of the test suite" | No such test or task exists (searched `tools/tasks`, `tools/tests`, all package tests; it is not on the roadmap). Its absence is why A04 went unnoticed. | Implement it (Phase 2 candidate) or mark the sentence "planned" in the three files. |
| A43 | U | S | `website/en/explanation/transport-model.md:104-110` | "One coroutine reads, accepts or receives at a time on an object. A second concurrent call raises an error instead of waiting."; "Create one buffered reader per stream. The library does not enforce it" | True for streams, listeners and `UdpSocket`, but a `BufferedReader` and a `BufferedWriter` do not raise: they serialise concurrent calls with a `Mutex` (`buffered_reader.lua:58`, OQ-29 (7); README net says "each reader and writer serialises its operations"). Whoever reads the page may expect an error from a second `reader:read_line()`. | Add "A buffered reader or writer queues the second call instead". |
| A44 | I | S | `website/fr/**` (front matter `source_revision`), `website/CLAUDE.md:7` | "each translated page has front matter `source_revision: <commit>` of the English page it translates" | `source_revision` is behind the English page on 12 of 16 pages (`git rev-list <source_revision>..HEAD -- en/<page>` is not empty: `explanation/multi-process-serving.md` (3 commits), `how-to/index.md` (6), `index.md` (3), `how-to/connect-and-serve-over-tcp.md` (2), `tls-client-and-server.md` (2), `udp-pipes-and-dns.md` (2), `run-processes-and-pass-connections.md` (3), `reference/glossary.md` (2), `reference/index.md` (2), `transport-model.md` (1), `deadlines-and-cancellation.md` (1), `log-structured-records.md` (1)). In most cases the French page was edited in the same commit as the English one (content is in step: same headings, blocks, numbers), so only the marker was not bumped. The planned `check-translations` (Phase 3) would flag all of them. | Bump `source_revision` on the pages verified to be in step. |
| A45 | I | S | `packages/net/CLAUDE.md:44-46` | a blank line splits the "Known pitfalls" list after the fourth bullet | Cosmetic: the list reads as two lists (generated template residue). | Remove the blank line. |

### Checked and found consistent (no finding)

- Names in README tables against code for `core` (all 38 public names), `reactor` (every function, class,
  option, default and error class listed), `net` (every function, class, option, default, error class, TLS
  reason): the only gaps are those in section 3.
- Error classes and codes: 11 classes of `core` plus `Error` (code = full class name), `reactor.IoError`,
  `reactor.TransportError` (a `core.NetworkError`), `net.EndOfStreamError`, `net.TlsError`,
  `net.TransportError` (the same class as the reactor's); all end in `Error`; the doc comment example is
  `hecate.http.FieldTooLargeError`.
- Options and defaults: `nodelay` true, `keepalive` false, `keepalive_delay` 60, `backlog` 128, `reuseport`,
  `family`, `limit` 65536, `capacity` 8192, `max_message` 16 MiB, `handshake_deadline` 10, `mode` "owner",
  socket path limits 107/103 bytes, Windows pipe name 256, read-ahead 64 KiB: identical in code, README,
  specification, the English website and the French website.
- ADR 0025 against `primitives.lua`, `reactor.lua:_create_computation` and `ambient_test.lua` (16 tests,
  including cancellation and the virtual clock); the ambient-context section of `concurrency.md` matches.
- ADR 0024 against `net/tls.lua`, the README and `explanation/tls-trust-and-security.md`
  (`ca_pem` adds anchors, `system_roots = false` requires `ca_pem`, verification cannot be disabled, the
  untrusted-issuer message names the remedy).
- Statements about `reuseport`, luv 1.53 and OQ-43 agree in the README, concurrency.md, the website (three
  places), the ADR and the open question; CI installs `1.53.0-0`.
- The glossary page of the website equals `docs/glossary.md` (links and brand adaptations aside); both have
  78 table rows in English and French; the French pages use the terms of `glossary-terms.md` (« échéance »,
  « portée », « tube de messages », « calcul », « contre-pression »...), apart from A37.
- No American spelling; no use of "task" for a computation in the three packages or the website; no
  `unsafe` in the net native crate; `check-glossary`, `check-docs-examples` and the tests of the three
  packages pass.

### Questions for the owner (not decided here)

A29 (add "ambient context" to the glossary despite the Phase 0 outcome), A33 (OQ-25 (6): `Condition:signal`
against the glossary), A40 (a specification for `net`), A41 (freeze of ADR 0007 and its heading), A42 (the
suspension-documentation test: build it or mark it planned).

## Phase 1 gate: coherence findings, part B (`json`, `log`, `doc`, benchmarks, tools)

Audit of the "Coherence" check of `docs/roadmap.md` ("Phase gates", item 3), method of
`docs/reviews/phase-0-coherence-findings.md`. Branch `claude/relay-phase-1-gate`, Linux, Lua 5.5.1. Read-only:
nothing was fixed or committed except this file.

### What was read

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

### Summary

32 findings: 16 U, 16 I. By size: 31 S, 1 M (B32), 0 D. Pure-Lua backend: no live statement remains in docs, README, website or CLAUDE
files (the hits are the OQ-53 history and one ADR note, all true); two comments still speak of "every backend" (B09).

### Findings

#### json

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

#### log

| ID | Sev | Size | Location | Quoted text | Problem | Fix |
|---|---|---|---|---|---|---|
| B11 | I | S | `packages/log/src/hecate/log/file_sink.lua:153-154` | "asynchronous flushing is a later step" | `AsyncSink` exists and is documented (README 52, logging.md 181-212). | "wrap it in an `AsyncSink` to move the write off the caller". |
| B12 | U | S | `packages/log/README.md:61` | "## Layout (once implemented)" | The package is implemented (status alpha). Also the status row starts "step 1" for a package that lists four steps. | "## Layout"; drop "step 1:" from Status. |
| B13 | U | S | `packages/log/README.md:46,56-59` vs `docs/architecture/logging.md:125-129,235-245` | README Public API table has no row for `log.bind` | `log.bind` is the one non-class function besides `Severity`/`severity_code` and has a `---@param` annotation; it appears only in prose after the table. | Add a table row `log.bind(fields, fn, ...)` with its two error classes (`ArgumentError`, `NonYieldableContextError`). |
| B14 | U | S | `README.md:46` (`redact`: "any depth") vs `logging.md:262,277` | "case-insensitive, any depth" / "any depth up to 16 levels" | The code stops at `MAX_REDACT_DEPTH = 16` (`logger.lua:14,23`); the README, website how-to (line 53-54) and CHANGELOG say "any depth" with no bound. Spec and README disagree. | Say "up to 16 levels" in README and how-to. |
| B15 | U | S | `website/en/how-to/log-structured-records.md:77-81`; example `packages/log/examples/hecate.log.AsyncSink.lua:1-2`; `packages/log/benchmarks/logger.lua:34` | "a detached coroutine writes to the target", "drain coroutine", "drain task" | README and logging.md call it the **drain computation** (glossary: computation = what `detach` starts); "task" is a glossary "instead of" term. Three names for one concept. | Use "drain computation" in the how-to, the example comment (the how-to embeds it, so `check-docs-examples` needs both changed) and the benchmark comment. |
| B16 | U | S | `CHANGELOG.md` entry "`hecate.log`, step 1" (line 33) | "`Logger` with a threshold", "a detached task driven by a `Semaphore`", "Open points in OQ-55 (the reactor has no ambient context yet; decided in ADR 0025, to be implemented)"; also line 32 "a task that is gone" | "threshold" is forbidden by glossary and OQ-60 ("never level or threshold"); "task" likewise; the OQ-55 remark is untrue since the ambient context is implemented (CHANGELOG line 18). | Reword: "severity", "computation"; delete the OQ-55 sentence. |
| B17 | U | S | `website/fr/how-to/log-structured-records.md:36` | "Les sévérités sont les huit de la RFC 5424" | `website/fr/glossary-terms.md:59`: severity = gravité, "jamais « niveau » ni « sévérité »". | "Les gravités sont les huit de la RFC 5424". |
| B18 | I | S | `docs/open-questions.md:96` and `:81-95` | the row starting `OQ-63`, `log`, qualified message prefix as the last line of the file | The row sits after the "OQ-55 addendum" and "OQ-56" prose sections, outside any table, so it renders as a stray line and OQ-63 is not in the "Resolved" table it belongs to (it is decided, "no new decision"). OQ-55 also has no entry of its own, only an addendum, though `logger.lua:188`, ADR 0025 and the roadmap cite "OQ-55" (phase-0 F37 flagged the duplicate id). | Move the OQ-63 row into "Resolved"; give OQ-55 a real row or reword the citations to ADR 0025. |
| B19 | I | S | `packages/log/README.md:3`, `init.lua:1`, `CLAUDE.md:8`, rockspec summary, `packages/README.md`, `llms.txt:54` | "per-scope context" | Documented exception (logging.md:229-230, phase-0 F02) but the package's own README never uses or links "ambient context" (ADR 0025), the term of `log.bind` and of `reactor`. A reader finds two names with no pointer in the README. | Add "(the ambient context of ADR 0025)" once in the README Responsibilities line "context propagation through reactor scopes". |
| B20 | I | S | `README.md:51` (`FileSink`) vs `file_sink.lua:187-189` | "a failed write raises `hecate.core.Error`" | Accurate; but `FileSink:write` after `close` silently returns (logging.md:161 says so, the README does not). | One clause in the README row. |

#### doc

| ID | Sev | Size | Location | Quoted text | Problem | Fix |
|---|---|---|---|---|---|---|
| B21 | I | S | `packages/doc/README.md:48-49` | "the first slice below has none, and the candidates are measured in spike OQ-39" | Untrue: the package now has third-party dependencies (comrak, syntect, two-face; README line 15 and ADR 0022 Accepted). Also `documentation.md:118-119` "the proposal is ADR 0022" while the same file's header says Accepted. | Rewrite both as "decided in ADR 0022 (Accepted)". |
| B22 | U | S | `docs/architecture/documentation.md:58` | "callout containers (`note`, `tip`, `warning`, `danger`)" | Callouts are GFM alerts NOTE, TIP, IMPORTANT, WARNING, CAUTION (README 120, `markdown.lua:35`, CHANGELOG). Also `markdown.lua:18` and `site.lua:187` call the fifth label `danger` for a CAUTION alert (`native/src/lib.rs:52`, `strings.lua:46,91` "Danger"), and `site.lua:187` passes no `important` label although `markdown.lua:18` lists one. | State the five alerts; name the label `caution` (or document that `danger` is the title of CAUTION) and pass `important`. |
| B23 | U | S | `packages/doc/README.md:11,138` and `:136` | "Limits of this first slice", "Phase 1 roadmap item" with "Roadmap phase 3" at line 10 | The table says phase 3 and the status says the minimal slice is done in Phase 1; the section name "first slice" survives the native-module rewrite. Not wrong, but the same package carries both labels. | "Limits of the current implementation"; keep phase 3 and say why in Status. |
| B24 | I | S | `packages/doc/src/hecate/doc/{build.lua:29,33,38,49,92; config.lua:43; front_matter.lua:13,82; luals.lua:76; site.lua:60,73; system_file_system.lua:23}` | e.g. `"cannot read site configuration " .. path`, `"invalid front matter at line 1: ..."` | The rule (phase-0 F34, OQ-63, coding-standards "Errors"): messages carry the qualified `module.function:` prefix. `json` and `log` follow it; these `doc` messages do not (others in `doc` do: `doc.build:`, `doc.Site:`). | Add `doc.load_config:`, `doc.build:`, `doc.front_matter.parse:` ... prefixes, or record the exception in OQ-63. |
| B25 | I | S | `packages/doc/README.md:63` | "`BuildError` ... `strict` problems" | Also raised for `SystemFileSystem` failures (`system_file_system.lua:23`) and LuaLS export failure (`luals.lua:75`); README lists only three causes. Minor. | Add the two causes. |
| B26 | U | S | `website/en/reference/index.md:12-17`, `website/fr/reference/index.md:17-20` | list of `core`, `reactor`, `net`, `json` only | `reference_site.DEFAULT_PACKAGES` is `core, reactor, net, json, log` (`reference_site.lua:16`, README 110), the home page says `log` is "implemented and documented", and a log how-to links to it. The reference index has no `hecate.log` entry. Also `.github/workflows/website.yml:118-121` checks only `core reactor net`. | Add the `hecate.log` line (EN and FR) and `json log` to the workflow loop. |
| B27 | I | S | `tools/tasks/gen_reference.lua:4`; `docs/architecture/automation.md` row `gen-reference` | "gen-reference [--packages core,reactor,net]"; "done for `core`, `reactor`, `net`" | The default set is now `core, reactor, net, json, log`; `packages/doc/bin/reference.lua:13` and `bin/build.lua:21` add only `json` (not `log`) to `package.path`, harmless because LuaLS reads the source, but the automation row is stale. | Update both texts. |

#### tools, automation catalogue, benchmarks

| ID | Sev | Size | Location | Quoted text | Problem | Fix |
|---|---|---|---|---|---|---|
| B28 | I | S | `docs/architecture/automation.md` section 1 (no row), `lua tools/run.lua --list` line `build-native` | (absent) | The catalogue does not list `build-native` (the only one of the 31 listed tasks missing; every other `--list` task has a row). `CLAUDE.md` and the README of json cite it as a command. | Add a row: `build-native <package>`, done, cargo or `cc`, installs into `.hecate/rocks`. |
| B29 | I | S | `automation.md` rows `format` / `format-check` and `check-annotations` | "formatter on Lua sources (and `clang-format` on C)"; `check-annotations` status "P1" | `--list` says "no formatter configured for the repository (OQ-3); always succeeds" and `CLAUDE.md` says the same. `check-annotations` is marked P1, no such task exists and Phase 1 is complete (ADR 0018 still cites it). | Rewrite the format row as a no-op until OQ-3; retime `check-annotations` (Phase 2 or an explicit deferral) and record it in the gate report. |
| B30 | I | S | `automation.md` row `bench` ; `tools/tasks/bench.lua:122` (`description`) | "`bench [name...] [--list] [--runs=N] [--pin=CPUS] [--out=DIR]`" | The task also takes `--yes`, `--strict`, `all` and the scenario form (`--rounds`, `--server-pin`, `--load-pin`, `--server-args`, `--compare`); the `--list` description lists neither. `benchmarks/README.md:53,75` uses `--rounds` for scenarios and `--runs` for micro-benchmarks, which no document explains. | One sentence in automation.md and in the task description: `--runs` for files, `--rounds` for scenarios. |
| B31 | U | S | `benchmarks/README.md:4`, `:10`, `:22`, `:92` | "their history is published on the website"; "`tcp-echo` ... 10 000 concurrent connections"; "memory, allocations per request"; "a C compiler, `cmake` and `cargo`" | (a) automation.md (`benchmarks.yml` row) says the history "comes later"; nothing is published. (b) The load generator defaults to 100 connections (`scenarios/tcp-echo/load.lua:24`) and the workflow uses 1000; 10 000 is only the documented example. (c) the scenarios print latency, throughput and errors only; no memory or allocation measure. (d) `cmake` is used by no task (`grep` over `tools/`). | (a) "will be published"; (b) "up to 10 000"; (c) "memory and allocations: not measured yet"; (d) drop `cmake`. |
| B32 | I | M | `website/fr/**` front matter `source_revision` | e.g. `how-to/log-structured-records.md:6` `ac925c3`; `reference/index.md` `cba7be6`; `index.md` `f1f3b5e` | 12 of 17 French pages are older than the English source by `git diff` (e.g. 4 lines of the log how-to, one line of the reference index, 7 of the home page). I compared the content of the pages in scope (json, log, index, how-to index, reference index) and they are in sync apart from B17; the revision stamp is what is stale, so `check-translations` (Phase 3) will flag them all. | Bump `source_revision` to the commit at which each page was last reconciled (after fixing B17), or record the deferral. |

### Checked and found coherent

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

## Phase 1 gate: coherence audit, part C (cross-cutting files)

Branch `claude/relay-phase-1-gate`, Linux, read-only audit. Coherence = every concept is named and described
identically everywhere, and nothing says something untrue.

### What was read (read this first)

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

### Summary

27 findings (C01 to C27): 2 U, 25 I. By size: 24 S, 3 D (C03, C17, C18). Plus six "not findings" notes (one M: French `source_revision` stamps).

### Findings

#### CI, tasks and automation

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

#### Layering and overview

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

#### Open questions

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

#### Roadmap wording

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

#### Status statements

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

#### Website and glossary

**C27 — U / S — `website/en/reference/index.md:10-20` (and `fr`), `.gitignore:29-32`, `website/OUTLINE.md`.**
`DEFAULT_PACKAGES` generates a `log` reference (`reference_site.lua:16`), and `website/en/index.md` says
"core, reactor, net, json and log packages are implemented and documented", but the reference landing page
(both languages) lists only core, reactor, net, json, so `log` reference pages are unreachable from it; the
generated `website/en/reference/log/` is not in `.gitignore` (the other four are), so it can be committed by
accident. `OUTLINE.md` omits the pages that exist: "Encode and decode JSON", "Measure performance" (the
"Logging and request context (P2)" entry has no file, though `how-to/log-structured-records.md` exists).
Fix: add `log` to both reference indexes and `.gitignore`; list the three pages in `OUTLINE.md`.

### Not findings, but to know

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

