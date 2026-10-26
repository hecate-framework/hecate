# Phase 0 gate: coherence findings (terminology and naming)

Scope of the audit: the "Coherence" check of `docs/roadmap.md` ("Phase gates", item 3), done as the
owner defined it: every concept is named and identified identically in every file. Reference
vocabulary: `docs/glossary.md` and ADR 0004.

Verified at branch `claude/relay-phase-0-gate` (up to date with `main`), on Linux.

## Method and coverage (read this first)

- Read in full: `docs/glossary.md`, `docs/vision.md`, `docs/developer-experience.md`, `docs/roadmap.md`,
  every file of `docs/architecture/`, `packages/README.md`, `README.md`, `AGENTS.md`, `CONTRIBUTING.md`,
  `llms.txt`, `website/CLAUDE.md`, `tools/README.md`, `tools/CLAUDE.md`, the READMEs of `core`, `reactor`,
  `net`, `log`, `http`, `router`, `schema`, `kernel`, `container`, `config`, the Responsibilities and
  Non-goals sections of the 17 other package READMEs, the `CLAUDE.md` of `reactor`, `net`, `log`, `kernel`,
  `http`, `router`, `schema`, `sql`, `query`, `orm`, `test`, `container`, `config`, and the agents
  `terminology-reviewer`, `translator-fr`, `pkg-kernel`, `pkg-reactor`.
- Checked by targeted search over the whole scope (all `docs/`, package READMEs and `CLAUDE.md`,
  `.claude/`, `website/en` and `website/fr`, `tools/`, root files) rather than read line by line: the ADRs
  (read in part: 0004, 0007, 0023, 0025; the others by search), `docs/open-questions.md`, the website pages
  (`en` and `fr`), the other `.claude/agents` and `.claude/commands`, the Lua sources (public identifiers,
  doc comments, error messages of `core`, `reactor`, `net`, `log`, `json`, `doc`).
- Mechanical checks run: the glossary deny-list (`promise`, `middleware`, `DTO`, `nursery`, `fiber`,
  `race`, `await`, `gather`, `event loop`, `cluster mode`, `service locator`, `task group`) over the whole
  documentation scope: no hit outside the glossary rows, the "instead of" columns, ADR 0003/0004 and the
  reviewer agent. All `reactor.*`, `net.*`, `log.*`, `json.*`, `core.*` names written in docs and website
  exist in the code (one exception: `reactor.shield`, correctly marked "not implemented" in OQ-23).
  The English glossary page of the website equals `docs/glossary.md` apart from the documented brand and
  link adaptations; the French glossary page uses the terms of `website/fr/glossary-terms.md`.
  British spelling is applied consistently in prose (finalise, behaviour, catalogue, artefact, cancelled,
  synchronisation: no American variant), except the one case in F30.
- Not covered: `docs/spikes/` (historical reports, excluded on purpose), the bodies of the ADRs not
  listed above, the Rust and C sources, `.github/`. Items marked "decision" need the owner: they choose
  between two names that are both defensible, and some touch an API not yet frozen.

Severity: **U** = user-facing (public API, user documentation, website, names a user types or reads);
**I** = internal (engineering docs, agents, tools, internal identifiers). Fix size: **S** = a few lines,
**M** = several files, mechanical; **D** = needs an owner decision first.

## Resolution (2026-10-26)

All findings were fixed in the pull request except those below. Owner decisions: F02 is not a finding
("ambient" is a scope; `log` keeps "per-scope context"); F17 verb-first (`connect_tcp`, `listen_tcp`,
`connect_pipe`, `listen_pipe`, `bind_udp`; `net.connect_tls` and `net.tls.connect` are different operations,
one-call client versus handshake over an existing stream, and stay); F34 qualified `module.function:`
prefix (runtime failures built from the operating system keep their shape); F19 the `hecate task` alias is
dropped (contributor tooling, not a CLI feature); F12 the README states the specification (eager loading is
explicit, lazy loading suspends, development warning on N+1). F07 decided by the owner (option B: `request.parameters.path.id`, `request.parameters.query.expand`,
`request.path` is the path string) and applied to the specification and the developer-experience document. Still open: F06 and F16 in part, now OQ-57 and OQ-58 in `docs/open-questions.md`. Not done:
the internal `task` record of `reactor` (optional, Phase 7); the French glossary page does not list the new
glossary rows yet (terms are in `website/fr/glossary-terms.md`); the strict website build could not run here
(no LuaLS, reference pages not generated). The uncovered areas of the audit remain uncovered.

## Summary

36 findings (F01 to F36): 28 user-facing (U), 8 internal (I). By fix size: about 26 small (S), 5 medium (M: F02, F14, F17, F26 translations, F03 internal rename), 5 needing an owner decision first (D: F07, F12, F17, F19, F34; F06 and F16 only in part).
No glossary deny-list term is used as an identifier or in a sentence of the documentation. The defects are
of three kinds: one concept with two names, one name with two meanings, and statements that went stale.

Top issues, in the order to fix them:

1. F01, F03: "unit of work" used for a coroutine (concurrency.md) and "task" used for a coroutine in
   public doc comments, README and the website (glossary: "task" is an "instead of" term).
2. F02: the central concept "ambient context" (ADR 0025, OQ-56: "There is no second name") is absent from
   the glossary, while `log` still calls it "per-scope context" in five places.
3. F04: "control channel" / "IPC channel" / "message channel" for the message pipe, in a specification and an
   Accepted ADR (glossary: "channel (reserved for communication between coroutines)").
4. F06, F07: the developer-experience document and the object-model specification disagree with ADR 0007 and
   with the code (`hecate.class`, `User:new`, "spelling settled during implementation", `request.path.id`).
5. F17: the same transport operations are named `tcp_connect`/`pipe_connect`/`udp_bind` in `reactor` and
   `connect`/`connect_pipe`/`bind_udp` in `net` (decision).
6. F10, F11: error classes without the `Error` suffix in the data-access specification; three names for the
   schema keyword `additional_properties`.
7. F12, F13: README claims contradicted by the specification (ORM "without N+1 by default"; SQLite "worker
   threads" while a worker is a process).
8. F24, F26, F28: stale or incomplete statements in `llms.txt`, `CONTRIBUTING.md`, the website page list and
   the Docker tag example.

## Findings

### A. One concept, several names

| # | Concept | Conflicting names, with files and lines | Canonical form (reference) | Sev. | Fix |
|---|---|---|---|---|---|
| F01 | Unit of work | `docs/architecture/concurrency.md:9`: "Every unit of work (request, background job, test) is a Lua **coroutine**". Glossary "unit of work" = Fowler's change-tracking object (`data-access.md:86`, orm README:24, orm CLAUDE.md:29). Same words, two concepts. | Reserve "unit of work" for the data-access pattern (glossary, Data table, Fowler 2002). In concurrency.md write "Every concurrent computation (request, background job, test) is a Lua coroutine", the wording the same file uses in the ambient-context section. | U | S |
| F02 | Ambient context | `packages/log/README.md:3` and `:24` ("per-scope context", "context propagation through reactor scopes (request id)"), `packages/log/CLAUDE.md:8`, `packages/log/src/hecate/log/init.lua:1`, log rockspec `summary`, `packages/README.md:13`, `llms.txt:50` (the last two generated from the README) versus `docs/open-questions.md:88-90` (OQ-56, owner: "the concept is the **ambient context** ... There is no second name"), ADR 0025, `concurrency.md:53`, `reactor.with_ambient`/`ambient`, `log/src/.../init.lua:33` ("ambient context"). The website how-to `website/en/how-to/log-structured-records.md:34-37` never uses the term. `docs/glossary.md` has no entry. | "ambient context" (ADR 0025, OQ-56). Replace "per-scope context" by "ambient context" or by "context fields" depending on what is meant (the logger's own `with_context` fields are not ambient). Add the glossary entry (see "Glossary proposals"). | U | M |
| F03 | Coroutine / computation vs "task" | Glossary "future ... Instead of: promise, task"; `concurrency.md` says "computation". Public text using "task": `docs/adr/0025-ambient-context.md:48,51,59` ("the running task", "bindings of a task"); `docs/open-questions.md:79` ("`reactor.detach` starts a task that outlives the caller"); `packages/log/README.md:52` ("a detached task writes to `options.sink`"); `packages/log/src/hecate/log/async_sink.lua:9,12,14,16,17,78,108`, `log/init.lua:19`, `log/file_sink.lua:8` ("calling task"); `packages/core/src/hecate/core/error.lua:120` ("closed while a task waited on it", doc comment of `ClosedChannelError`, which feeds the reference); `website/en/how-to/log-structured-records.md:78,80,85,86` ("a detached task writes to the target", "stops the task"). Internal: `reactor.lua` (57 uses of `task`), `primitives.lua`, `scope.lua`, `condition.lua`, `monitor.lua`, `internal/context.lua` (`current_task`, `cancel_task`, `notify_cancel(task)`), `Reactor:_create_task`. | "computation" for the running unit of the scheduler, "coroutine" when the Lua object is meant, "detached computation" for `reactor.detach` (concurrency.md, glossary coroutine/future). The `check-glossary` deny-list cannot catch it (identifier `task` is context dependent): record it in the reviewer checklist. Public doc comments, README and website first; renaming the internal `task` record is optional (M) and can wait for Phase 7 (decision on whether internals follow the glossary). | U (public), I (internal record) | S public / M internal |
| F04 | Message pipe | Glossary "message pipe ... Instead of: channel (reserved for communication between coroutines)". `docs/architecture/concurrency.md:137-138`: "over a control channel ... a worker whose control channel closes drains and exits"; `docs/adr/0023-multi-process-serving.md:80`: "`reactor.ipc`: a framed message channel between a parent and its child", `:108-110`: "The control channel ... an IPC channel to the primary ... sees the channel close". The website, the reactor README (`:80`) and the French pages already say "message pipe" / "tube de messages". | "message pipe" (glossary; ADR 0023 itself defines it), "control message pipe" if a qualifier is needed. | U | S |
| F15 | Action vs handler | The specification names the user code run by a route an **action** (`http-and-routing.md:57,63`, kernel README:25, overview diagram, glossary "chain of responsibility: ordered handlers around an action"). `README.md:58` and `website/en/index.md:29` ("Handlers read like sequential code"), `website/en/explanation/transport-model.md:42` ("Your handler"), `website/fr/index.md:30` and `website/fr/explanation/transport-model.md:46` ("Les gestionnaires"/"Votre gestionnaire"). `reactor` also uses "handlers" for libuv completions (glossary reactor row), and ADR 0006:11 "handlers". | "action" in text about routes and controllers; "handler" only for I/O completion handlers (glossary reactor). Add "action" to the glossary (see proposals). French: « action ». | U | S |
| F36 | Route modules, request scope | `packages/kernel/README.md:23` "`routes` modules" (spec, ADR 0006, kernel summary and `llms.txt`: "route modules"); `kernel/README.md:25` "request scope; container scope per request" (three scopes for two concepts: the reactor scope of the request and the container lifetime `scoped`, container README:"scoped (per reactor scope, e.g. request)"); `packages/hecate/README.md` "problems" re-exported versus "problem details" everywhere else (`hecate.problem.*` is the namespace). | "route modules" (the factory is `hecate.routes(name)`); "request scope" for the reactor scope and "scoped lifetime" for the container; "problem details" in prose, `hecate.problem` as the namespace. | U | S |
| F17 | Transport function names across `reactor` and `net` | `reactor`: `tcp_connect`, `tcp_listen`, `pipe_connect`, `pipe_listen`, `udp_bind` (reactor README:67-71, concurrency.md:100). `net`: `connect`, `listen`, `connect_pipe`, `listen_pipe`, `bind_udp`, `connect_tls`, and `tls.connect` / `tls.accept` (net README:60-100; `net/src/.../udp.lua`, `pipe.lua`, `tls.lua`; used in `website/en` and `website/fr` how-tos, tests and examples). Same operation, noun-verb in one package and verb-noun in the other, and `connect_tls` next to `tls.connect`. | Decision (public API, not frozen). One order for the whole framework: e.g. verb-noun everywhere (`connect_pipe`, `bind_udp`) or noun-verb everywhere. The rename touches READMEs, 2 spec files, en/fr how-tos, examples and tests. Cite glossary rule 4 (snake_case) only; no glossary term decides it. | U | D+M |
| F34 | Error message prefix | `packages/json/src/hecate/json/init.lua:72`: "`json.%s: unknown option %s`" (qualified); `net/udp.lua:40` "`bind_udp: unknown option`", `reactor/process.lua:216` "`spawn: unknown option`", `reactor/dns.lua:47` "`resolve: unknown option`" (unqualified), `buffered_reader.lua:43` "`BufferedReader: unknown option`". `coding-standards.md` ("Errors") fixes the message shape but not the prefix. | Decision: qualified (`net.bind_udp:`) or bare; then state it in coding-standards.md "Errors". Qualified is unambiguous across packages (`resolve` exists in both `reactor` and `net`). | U | D+S |

### B. One name, several meanings

| # | Concept | Conflicting uses, with files and lines | Canonical form (reference) | Sev. | Fix |
|---|---|---|---|---|---|
| F14 | entity / service / module / controller / route module / action | Used as architecture terms but absent from the glossary: "entities" in `data-access.md:84-98`, `schemas-and-contracts.md:44`, `cli-and-packaging.md:36`, ADR 0007/0011, vision.md:23, DX `orm.Entity`, orm README:23; "services" (container bindings, vision.md:23, ADR 0007:64); "module" has three meanings: kernel feature module (`http-and-routing.md:67`, DX `module.lua`), Lua module `hecate.<name>` (`overview.md` "Naming"), and "meta-module" `hecate`; "package", "rock" are used with fixed meaning in `packages/README.md` but not defined. | Add entries (see "Glossary proposals"), and write "feature module" for the kernel concept everywhere (kernel README:23 already does). | U | M |
| F16 | schema | Glossary: "schema = declaration of a type usable for validation, coercion and contract emission". Also used for the database schema: `data-access.md:91` ("the schema produced by migrations"), `:104` ("a schema-definition API"), `packages/query/README.md` ("schema-definition API used by `migration`"), "schema migrations" (migration README:3, packages/README.md:24). Ownership of the "schema-definition API" is also unclear: `query` README says it lives in `query`; `data-access.md:104` lists it under `migration`. | Keep "schema" for the type declaration. For the database use "database schema" (SQL standard term) and add it to the glossary; record in one place which package owns the DDL API. | U | S+D |
| F18 | pipe | `PipeStream`/`pipe_connect`/`pipe_listen` are a Unix-domain socket (named pipe on Windows) (reactor README:71); a "message pipe" is the framed `reactor.ipc` connection (glossary); POSIX `pipe(2)` is the glossary reference of the latter. In French all three read "tube" (`website/fr/how-to/udp-pipes-and-dns.md` and `run-processes-and-pass-connections.md`). | Keep both names, but document in the glossary row "message pipe" that `PipeStream` is a different thing (local stream socket), and add « socket Unix / tube nommé » to `website/fr/glossary-terms.md`. | U | S |
| F32 | selection | Glossary rule 3 reserves *selection* for relational algebra. `docs/architecture/testing.md:54` has a feature row "Selection | by file, case, test name pattern, tag". | "Test selection" is the usual xUnit word but collides with σ: use "Filtering by ..." only if "filter" is not taken (it is: glossary "filter" = chain element), so propose "Targeting" or "Choosing tests". Low priority. | I | S |
| F33 | column vs attribute | `data-access.md:33`: "`ResultSet`: iteration over tuples, column metadata". Glossary: attribute (instead of column, in the ORM API; "column" stays correct for SQL DDL). `ResultSet` is the SQL-level interface, so "column" is defensible here; the sentence mixes both vocabularies ("tuples" and "column"). | Decide the level: either "attribute metadata" (relational vocabulary, as in "tuples") or "tuple" -> "row" with "column" for the SQL level. Recommend attribute metadata for consistency with the glossary. | U | S |

### C. Names that differ between specification, ADR, README, website and code

| # | Concept | Conflicting names, with files and lines | Canonical form (reference) | Sev. | Fix |
|---|---|---|---|---|---|
| F06 | Class declaration and instantiation | DX `developer-experience.md:77,152`: `hecate.class("UserController", hecate.Controller)`, `:163`: `User:new { email = ... }`; ADR 0007 "Final spelling" and `packages/core/README.md`: `core.class(name, superclass?, options?)`, instance by `Class(...)` (calls `init`), `core.finalise(C)` required first. `object-model.md:63`: "The exact spelling ... is settled in ADR 0007 during implementation" (it is settled). | ADR 0007 spelling. DX is "illustrative" but is the north star for users: use `core.class` or state what `hecate` re-exports (`hecate.class` needs a decision for the meta-module), `User { email = ... }` or `User(...)`, add `core.finalise`. Rewrite object-model.md:63 as past tense. | U | S (+D for the `hecate.class` alias) |
| F07 | `request.path` | `http-and-routing.md:24-25`: a request exposes `method`, `target`, `path`, `query`, `fields`, "parsed `path` parameters after routing"; DX `:93,129`: `request.path.id`. `path` would be both the target's path string and the table of path parameters; `query` likewise (query string vs parsed parameters). Route declarations use `parameters = { path, query, fields, cookies }`. | Decision: e.g. `request.target`/`request.path` (string) and `request.parameters.path.id`, or keep `request.path.id` and rename the string. Make spec and DX agree. | U | D |
| F08 | body vs content | RFC 9110 (glossary HTTP section): *content*. `packages/http/README.md:23`: "limits (header size, body size, timeouts), streaming bodies"; the specification says "content length", `request:content()`, "validated `content`". | "content" (RFC 9110): "limits (field size, content size, deadlines), streamed content". | U | S |
| F09 | header vs field; remote vs peer address | Glossary: *field* (header field). `docs/adr/0018-error-signalling.md:30` ("`headers:get(name)`"), `docs/adr/0006-declarative-routes-as-runtime-data.md:15` ("path/query/header/content" parameter locations: OpenAPI term, then keep `header` only when quoting OpenAPI, since the route declaration key is `fields`), `http/CLAUDE.md` "header folding" (RFC 9112 term, fine). `http-and-routing.md:25`: "the connection's remote address" versus `peer_address()` on every `net` stream and the glossary's "peer". | "fields" and `fields:get(name)` in examples; `peer_address` for the request's remote address. Note the OpenAPI mapping `fields` <-> `in: header` once in the specification. | U | S |
| F10 | Error class naming and code | All 15 implemented error classes end with `Error` and have `code` equal to the full class name (`core/error.lua:104-131`, `net/errors.lua`, `json/errors.lua`, `reactor/internal/uv_call.lua:8,14`). `data-access.md:50-51` specifies `ConnectionError`, `IntegrityViolation`, `SerializationFailure`, `DeadlockDetected`, `SyntaxError`; `coding-standards.md:68` gives the code example `hecate.http.HeaderTooLarge` (no suffix, and "header" instead of "field"). Also `ConnectionError` (sql) next to `NetworkError`/`TransportError` and `SyntaxError` shadowing the common Lua/other-language name. | Suffix `Error` and code = `hecate.<package>.<ClassName>`: `IntegrityViolationError`, `SerializationFailureError`, `DeadlockDetectedError`, `hecate.http.FieldTooLargeError`. | U | S |
| F11 | Unknown properties keyword and base types | `schemas-and-contracts.md:17`: option `additional`; `:40`: "Unknown properties"; `packages/schema/CLAUDE.md:43`: "`additional_properties` default". `packages/schema/README.md` "primitive and refinement types" versus the specification table "Base" and glossary "A base type restricted by predicates"; `object { field = schema }` (spec) versus "properties"/"fields". | `additional_properties` (JSON Schema `additionalProperties` in snake_case, glossary rule 4 and JSON Schema paragraph); "base types" (glossary refinement type); "properties" for members of an `object` schema (JSON Schema term), "fields" only for HTTP header fields. | U | S |
| F12 | ORM loading | `packages/orm/README.md:27`: "lazy and eager loading without N+1 by default"; `data-access.md:92-94`: "explicit eager loading ... is the default recommendation; lazy loading suspends transparently, and the ORM warns in development when it detects N+1". A promise versus a warning. | The specification (ADR 0011 is still Proposed; spike OQ-18 decides): README should say "eager loading is explicit; N+1 detected and warned in development". | U | D (small text once decided) |
| F13 | worker | Glossary: "worker = a process with its own reactor ... workers share nothing", "child process" for the OS relation. `packages/sqlite/README.md:23` "connections executed on worker threads"; `packages/sqlite/CLAUDE.md:28` "from worker threads"; the same package's summary, roadmap:217, data-access.md:12, ADR 0002/0014 say "libuv thread pool". Also `packages/test/README.md` "parallel workers" (fine: processes, testing.md "worker processes"). | "libuv thread-pool threads" ("pool threads" in concurrency.md:112) in sqlite README and CLAUDE.md. | U | S |
| F35 | Same limit stated two ways | `packages/net/README.md:90`: Unix socket path "104 bytes on macOS, 108 on Linux" (also the French page `website/fr/how-to/udp-pipes-and-dns.md:140`, "104"); `packages/reactor/README.md:71`: "limited to 107 bytes (103 on macOS)". One counts the terminating NUL, the other does not. | State once ("at most 107 bytes (103 on macOS), excluding the terminating NUL") and reuse in net README, reactor README, doc comments and both website languages. | U | S |
| F05 | reactor non-goals and agent scope | `packages/reactor/README.md:34`: non-goal "`offload` and worker process primitives (OQ-8): Phase 2 follow-up (OQ-27)", while the same README implements `spawn`, `ipc`, `reuseport` (`:63-65`) and roadmap:166 ticks them. `.claude/agents/pkg-reactor.md:3,10` lists "thread-pool offloading" in the scope although `offload` is not implemented (concurrency.md:34). | README non-goal: "`offload` (OQ-27)". Agent scope: "(offload pending)". | U | S |

### D. Statements that are stale or not true

| # | Statement | Where | Fact and fix | Sev. | Fix |
|---|---|---|---|---|---|
| F24 | "specification stage, no implementation yet" | `llms.txt:5-6` (not covered by `gen-llms-txt`, which regenerates only the package list); `CONTRIBUTING.md:3` ("Hecate is at the specification stage") | `README.md` says "early implementation"; six packages exist. Align the two files on the README wording. | U | S |
| F26 | Website page lists | `llms.txt:30-39` lists 9 website pages; `website/en/how-to/` also holds `encode-and-decode-json.md`, `log-structured-records.md`, `measure-performance.md`, absent from `llms.txt`; `website/fr/how-to/` lacks their translations (`website/fr` has 13 pages, roadmap:97) | List the three pages in `llms.txt`; add the three translations or record them as pending in `website/fr` (fallback to English exists, documentation.md "Translations"). | U | S (list) / M (translations) |
| F25 | Front matter | `website/CLAUDE.md:11`: "Each page front matter: `title`, `description`, `hecate`, `lua`"; `docs/architecture/documentation.md` ("Content conventions", OQ-35): `title` optional, the page title is the `#` heading; 12 of 15 English pages have no `title`. | Change `website/CLAUDE.md` to "`description`, `hecate`, `lua`; `title` only to override the navigation label". | I | S |
| F27 | Native code table | `docs/architecture/overview.md:90-91`: "HTTP/1.1 parsing | llhttp | OQ-6", "JSON | C codec | OQ-5". ADR 0019 (Accepted) decides llhttp; ADR 0020 decides a C decoder (yyjson) and a Rust encoder (serde_json), no fallback; the TLS row already cites its ADR. `packages/http/README.md:15` also cites OQ-6. | "JSON | yyjson decoder (C), serde_json encoder (Rust) | ADR 0020, ADR 0021"; "llhttp | ADR 0019"; same in http README. | U | S |
| F28 | Docker names | `docs/architecture/versioning-and-distribution.md:26`: tag `hecate:0.3.0-lua5.5-debian`; images are `hecate/runtime`, `hecate/build`, `hecate/dev` (`:87-89`, `docker/README.md:8-12`, tag `0.3.0-lua5.5-debian`). | `hecate/runtime:0.3.0-lua5.5-debian`. | U | S |
| F19 | `hecate task` | `docs/architecture/automation.md:10`, `docs/adr/0015-ci-cd-on-github-actions.md:16`, `.claude/commands/check.md:7`: "`hecate task <task>` is an alias". No such command in the table of `docs/architecture/cli-and-packaging.md`, nor in the `packages/cli/README.md` responsibilities ("all commands in cli-and-packaging.md"). | Add `hecate task <task>` to the CLI specification or drop the alias (the CLI is Phase 3; this is a decision of the CLI scope). | I | D (small text) |
| F20 | Files that do not exist | `tools/README.md:17` and `tools/CLAUDE.md:8`: `tools/bootstrap/versions.lua` "pinned versions and SHA-256 checksums" (pins are in `bootstrap.sh`: `LUA_VERSION=5.5.1`, `LUAROCKS_VERSION=3.13.0`, and `bootstrap.ps1`); `tools/README.md:20`: `services/compose.yaml` in the layout (`automation.md` says `services` is P4; the directory does not exist). | Describe where the pins really live; mark `services/` as planned. | I | S |
| F21 | Task catalogue | `automation.md:68`: `new-package <name> --layer L`; the task is `new-package <name> --layer "<label>" --phase <n> --summary "<text>" [--deps a,b]` (`--list`, `packages/README.md:43`). `gen-rockspecs` exists (`lua tools/run.lua --list`) but has no row in automation.md ("Generators"), while tools/CLAUDE.md requires every task in the catalogue. | Fix the `new-package` row; add `gen-rockspecs`. | I | S |
| F22 | Status words | `packages/README.md:41` defines `specified`, `planned`, `in progress`, `alpha`, `stable`; the generated table shows `implemented` (core README:11), `Lua API on two native modules` (json README:11), `step` (log README:11), `minimal slice done` (doc README:11): the catalogue takes the first words of each README "Status" cell. Also reactor and net are "in progress" while their roadmap items are ticked and core is "implemented". | Start every Status cell with one word of the list; put the detail after the dash (as `net` and `reactor` do): `in progress`/`alpha`, with the rest after " — ". Add the word the roadmap implies for "done, API not frozen" (`alpha`, or add `implemented` to the list). | U | S |
| F23 | Layer labels | `packages/websocket/README.md:7` "Protocol", `packages/security/README.md:7` and `packages/template/README.md:7` "Framework" (also `packages/README.md` rows), versus `overview.md` (websocket in "Layer 2 — Protocol", security and template in "Layer 3 — Framework") and the numbered labels "2 — Protocol", "3 — Framework" of the other packages. `README.md` "Components" puts them in a separate "Planned" row instead of their layer. `boundaries.rank` accepts both, so no check fails. | Number the labels (`2 — Protocol`, `3 — Framework`); in `README.md` keep one layer per package and show planned status in the catalogue only. | U | S |
| F29 | Command lists | `.claude/commands/` has 11 commands including `relay.md`; `CLAUDE.md:80-81` and the table of `ai-assisted-development.md` ("Commands") list 10 and omit `/relay` (described in a separate section). | Add `/relay` to both lists. | I | S |

### E. Spelling and wording conventions

| # | Concept | Conflicting forms, with files and lines | Canonical form | Sev. | Fix |
|---|---|---|---|---|---|
| F30 | licence / license | `automation.md:39,46` "licenses", `:119-120` "Licences:" "licence fails CI"; `roadmap.md:51` "licences"; `tools/README.md:21` "licences tasks"; the task is `check-licenses`. Everything else in the prose is British (see Method). | Prose: "licence" (noun), consistent with the repository's British spelling; keep `license` in external identifiers (rockspec `license`, SPDX, badge, task name `check-licenses`). State the rule once in `coding-standards.md` ("Naming"): British spelling in prose and identifiers (`finalise`, `normalise_config`), with the task name as the documented exception. Also `tools/lib/coverage.lua` and `tasks/coverage.lua` use `normalize` against `hecate.doc` `normalise_config`. | I | S |
| F31 | script vs task | `automation.md:1,5,7,13,19` ("Script catalogue", "scripts are thick", column "Script"), ADR 0015 title "scripts in Lua", `tools/README.md:3`; versus "task" in `CLAUDE.md`, `tools/CLAUDE.md`, `lua tools/run.lua <task>`, `--list`, the same file's later tables. | "task" for what `tools/run.lua` runs; "script" only for files such as `bootstrap.sh`. | I | S |

## Glossary proposals (to add in the same pull request as the fixes; ADR 0004)

| Term | Meaning | Reference | Instead of |
|---|---|---|---|
| ambient context | Immutable key-value bindings visible in a computation and in the computations it forks or detaches (`reactor.with_ambient`, `reactor.ambient`, `log.bind`) | ADR 0025; Swift task-locals, Java `ScopedValue` (as cited there) | thread-local, task-local, `local` (OQ-56) |
| computation | A running unit of the scheduler: a coroutine started by `fork`/`detach` or the main coroutine; what a scope owns and a future stands for | concurrency.md ("computation") | task |
| suspension point / suspend | A call at which the running coroutine yields to the reactor; every I/O operation and every primitive of `hecate.reactor` | concurrency.md "Suspension points" | blocking (a suspended call does not block the reactor), async |
| action | The controller method or function a route invokes; what filters wrap | http-and-routing.md | handler (reserved for I/O completion handlers) |
| controller / route module / feature module | The two route declaration styles (ADR 0006) and the kernel's grouping of them | ADR 0006; http-and-routing.md | router group, blueprint, plugin (other ecosystems); "module" alone is ambiguous with a Lua module |
| entity | A class whose instances have an identity and are persisted by a mapper | Evans (2003) | model, record |
| database schema | The set of relations, constraints and indexes of a database (SQL DDL), not a `hecate.schema` type declaration | ISO/IEC 9075 | schema (alone, in data access) |
| problem details | An RFC 9457 error representation (`hecate.problem.*`) | RFC 9457 | error response, error DTO |
| service | An object registered in the container and resolved by it | Fowler (2004) | bean, provider |
| peer | The remote end of a connection (`peer_address`) or of a message pipe (`Peer`) | RFC 9293 | remote (in `remote address`), client (when the role is unknown) |

Also add to `website/fr/glossary-terms.md` the French term of each entry added above (« contexte ambiant »,
« calcul » for computation, « point de suspension », « action », « entité », « schéma de base de données »,
« détails de problème », « service », « pair » already present) so that `translator-fr` has a decision to apply.

## Checked and found consistent (no finding)

- Glossary deny-list terms: absent from identifiers, comments, error messages, READMEs, website (en and fr).
- Concurrency primitives (`fork`, `join`, `select`, `deadline`, `scope`, `Channel`, `Semaphore`, `Mutex`,
  `Monitor`, `Condition`, `detach`, `with_ambient`) are spelled the same in concurrency.md, the reactor README,
  the code, the website and the French glossary terms.
- `deadline` versus `timeout`: no `timeout` option exists in the code; the docs state "no timeout argument,
  use `deadline`" consistently (net README:73, concurrency.md:105, website how-tos); the only prose uses are
  `http/README.md:23,25` ("timeouts", "timeouts/deadlines": folded into F08) and "idle timeout" idiom.
- Package names, rock names, layer graph (`overview.md` generated block against the READMEs), the 32 tasks of
  `lua tools/run.lua --list` against `CLAUDE.md` "Commands", option names `handshake_deadline`,
  `keepalive_delay`, `max_message`, `system_roots`, `ca_pem`, `client_ca_pem` (code, README, website).
- French pages use `échéance`, `portée`, `tube de messages`, `primaire`, `flux`, `contre-pression`, `fermeture
  partielle`, `n-uplet` as in `website/fr/glossary-terms.md`.
- The brand rule (the name `hecate` is never capitalised on the website, `Hecate` in engineering documents) is
  applied in both places.
