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

Every finding of the three passes (F01 to F75) is fixed in this pull request, with the owner's decisions:
F02 is not a finding ("ambient" is a scope; `log` keeps "per-scope context"); F06 `core.class`, no
`hecate.class` alias (OQ-57); F07 `request.parameters.path.id`, `request.parameters.query.expand`,
`request.path` is the path string; F12 the README states the specification; F16 and the data-access layering
(OQ-58, [ADR 0026](../adr/0026-query-sql-layering.md), Proposed): abstract API in `query`, translators in
`sql`, drivers transport only; F17 verb-first transport names; F19 `hecate task` dropped; F34 qualified
`module.function:` prefix everywhere, with one documented exception (cancellation signals and the direct
`coroutine.yield` report, which involve no call the caller wrote); OQ-60 `severity` in `log`; OQ-61
`duplicate_member_name` in `json`. The internal `task` record of `reactor` is renamed `computation`, the
French glossary page equals the English one.

Left, by their nature: F75 (the missing specification sections of `container`, `config` and `log`) is not a
vocabulary defect: OQ-62 is resolved by the owner (2026-10-26): the `log` section is written
([logging.md](../architecture/logging.md)), those of `container` and `config` are written when the packages are
implemented (Phase 2); `SyntaxError` in `data-access.md` ends in `Error`
and was not renamed. Not verified here: `typecheck` and the strict website build (they need LuaLS, which could
not be run in this environment); CI runs both. Out of scope by nature: vendored yyjson, binary files,
`Cargo.lock` and generated data (see the third pass).

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
| F32 | selection | Glossary rule 3 reserves *selection* for relational algebra. `docs/architecture/testing.md:54` has a feature row "Selection \| by file, case, test name pattern, tag". | "Test selection" is the usual xUnit word but collides with σ: use "Filtering by ..." only if "filter" is not taken (it is: glossary "filter" = chain element), so propose "Targeting" or "Choosing tests". Low priority. | I | S |
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
| F27 | Native code table | `docs/architecture/overview.md:90-91`: "HTTP/1.1 parsing \| llhttp \| OQ-6", "JSON \| C codec \| OQ-5". ADR 0019 (Accepted) decides llhttp; ADR 0020 decides a C decoder (yyjson) and a Rust encoder (serde_json), no fallback; the TLS row already cites its ADR. `packages/http/README.md:15` also cites OQ-6. | "JSON \| yyjson decoder (C), serde_json encoder (Rust) \| ADR 0020, ADR 0021"; "llhttp \| ADR 0019"; same in http README. | U | S |
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

## Second pass (2026-10-26)

Scope: the areas the first audit did not read in full. Decisions applied as given (verb-first transport names,
qualified `module.function:` prefixes, `request.parameters.path`, `core.class`, ADR 0026, "computation", "message
pipe", "action", "feature module", `Error` suffix, British spelling). Not touched, by instruction:
`packages/reactor/src`, `packages/reactor/tests` (another agent renames the internal `task` record and error
shapes), `website/fr/reference/glossary.md`.

### Files read

- Read in full: all 26 ADRs, the ADR index and template; `docs/open-questions.md`; the text reports of
  `docs/spikes/` (OQ-1, 2, 3, 6, 41 in full; OQ-4, 5, 8, 11, 39, 44, 52 and the OQ-8 notes by term scan of every
  line, because they are measurement logs); every page of `website/en` and `website/fr` (prose; the code blocks of
  each French page were compared with the English one: identical), `website/CLAUDE.md`, `OUTLINE.md`, `README.md`,
  the French README and `glossary-terms.md`; all `.claude/commands` and `.claude/agents` (reviewers in full, the
  28 package agents by description and scope); `.github` (CODEOWNERS, labeler, labels, templates, mirror template,
  relay template, workflow comments and step names); `tools/README.md`, `tools/CLAUDE.md`, `tools/cloud/README.md`,
  the task catalogue, `tools/lib/glossary.lua`; `benchmarks/` (README and sources) and `examples/`; the doc comments,
  identifiers and error messages of `core`, `net`, `json`, `log` and `doc` (`src`), and a term scan of the Rust and
  C sources and of the remaining `tools` sources. Generated `website/dist` and vendored code excluded.

### Findings

| # | Where | Defect | Fix | Status |
|---|---|---|---|---|
| F37 | `docs/open-questions.md` | Two different entries named OQ-55 (log ambient context, referenced by ADR 0025, `log`, roadmap; `cargo deny` policy of `doc`, referenced by `deny.toml`). Rows OQ-57 and OQ-58 sat after prose, outside the Resolved table. | `doc` policy renumbered OQ-59 (table and `deny.toml`); rows moved into the table. | fixed |
| F38 | ADR 0001, 0004, 0005, 0015 (and index) | "script" for a task of `tools/run.lua` (F31 had not reached the ADRs). | "task"; ADR 0015 title now "tasks in Lua", index updated. | fixed |
| F39 | ADR 0023, `website/en` and `fr` multi-process pages | "handlers" for the code above the listener (glossary: action). | "actions". | fixed |
| F40 | ADR 0025, OQ-30, OQ-50, OUTLINE | "hidden channel", "a task waits", "one task reads", "CPU-bound tasks", "handler receives the request body", "typed route bodies". | flow, computation, action, content (RFC 9110). | fixed |
| F41 | ADR 0026 follow-through | Query/sql CLAUDE.md files still gave `query` a dependency on `sql`, rendering invariants and per-dialect tests; summaries said "rendered per SQL dialect"; migration "schema migrations"; mysql "dialect detection". | CLAUDE.md of `query` and `sql` rewritten, summaries updated in READMEs, rockspecs, catalogue, `llms.txt`, agents and labels (generators report in step); `migration`: "database schema"; `mysql`: descriptor. | fixed |
| F42 | `log` API | The least urgent severity recorded is `level` (option, `set_level`, `level()`, `is_enabled`), "threshold" (comments) and `Severity` (class, RFC 5424). | OQ-60 (decision). | open |
| F43 | `json` | Reason `duplicate_key` versus RFC 8259 "member name" used in the prose. | OQ-61 (decision). | open |
| F44 | `.claude/agents/pkg-*.md` | Descriptions generated with a lower-cased first letter: "hTTP/1.1", "mySQL", "tCP/UDP", "openAPI", "postgreSQL", "sQLite", "microsoft", "mongoDB", "webSocket", "redis". `pkg-kernel`: "modules" for feature modules. `ci-engineer`: "scripts" for tasks. | corrected. | fixed |
| F45 | `terminology-reviewer` | The context-dependent misuses of F03 and F31 were not in its checklist. | paragraph added. | fixed |
| F46 | `website/fr` | `README.md` said three pages were untranslated (all exist); the reference index lacked `hecate.json`. | both corrected. | fixed |
| F47 | `core/error.lua`, its test | Doc example code `hecate.http.HeaderTooLarge` (no `Error` suffix, "header"), contrary to F10. | `hecate.http.FieldTooLargeError`. | fixed |
| F48 | `net/tcp_stream.lua` | "Address of the remote end" for `peer_address`. | "Address of the peer". | fixed |
| F49 | `doc` | Messages named `doc.SystemFilesystem`, `doc.MemoryFilesystem` (classes are `...FileSystem`); module files `filesystem.lua`, `memory_filesystem.lua`, `system_filesystem.lua` against `FileSystem`. | messages fixed; files renamed `file_system.lua`, `memory_file_system.lua`, `system_file_system.lua` (and the test). | fixed |
| F50 | `tools` | `coverage.normalize` against British `normalise` used elsewhere (F30 residue). | renamed. | fixed |
| F51 | `benchmarks/README.md` | `tools/bootstrap.sh` (the file is `tools/bootstrap/bootstrap.sh`). | corrected. | fixed |

### Left

- OQ-60 and OQ-61: two names for one concept in public API; the owner chooses.
- The French glossary page does not list the new rows (excluded by instruction).
- `.github/dependabot.yml` watches only `packages/net/native`, not the `json` and `doc` crates: not terminology,
  reported for the CI owner.
- Spike reports keep the vocabulary of their time (HTTP "headers" in the llhttp report, "task" for Swift or tokio):
  historical measurements, left as written.
- Not run: the strict website build (no LuaLS here).

## Third pass (2026-10-26)

Scope: the areas the second pass admitted it had not read line by line. Everything below was read in full unless
the last list says otherwise. Not touched, by instruction: `packages/reactor/src`, `packages/reactor/tests`,
`packages/net/src`; OQ-60 and OQ-61 left to the owner.

### Files read

- (a) `.claude/agents`: the 13 non-package agents and all 28 `pkg-*` agents, each read in full (the 28 share one
  template: every file was read, and the scope, description, documents to read, allowed dependencies and standards
  of each were compared with the package README, the "Specification" row of the README and the rockspec; the
  comparison is now also a test, `tools/tests/agent_test.lua`).
- (b) `.github`, every file: `CODEOWNERS`, `dependabot.yml`, `labeler.yml`, `labels.yml`, `pull_request_template.md`,
  the 5 issue templates and `config.yml`, `mirror-template` (README, READ-ONLY, workflow), `relay/HANDOFF.template.md`,
  and the 10 workflows (`ci`, `claude`, `docs`, `pr-hygiene`, `labels`, `security`, `website`, `benchmarks`, `native`,
  `nightly`), including comments, job and step names. Also `lychee.toml` and `deny.toml` (they are referred to by the
  workflows).
- (c) Native code: `packages/json/csrc/native.c` (482 lines), `packages/json/native/src/lib.rs`,
  `packages/net/native/src/lib.rs`, `packages/net/native/tests/robustness.rs`, `packages/net/native/fuzz`
  (`build.rs`, the 4 targets, README), `packages/doc/native/src/lib.rs`, the three `Cargo.toml`, the fuzz
  `Cargo.toml`, `rust-toolchain.toml` and `.cargo/config.toml`.
- (d) `tools/` in full: `run.lua`, `harness`, `hooks`, all 19 `lib` files, all 32 tasks, all 20 test files,
  `bootstrap` (both scripts and the CMake file), `cloud` (README and `setup.sh`), `README.md`, `CLAUDE.md`.
  `packages/doc/src` in full: every Lua module (`build`, `config`, `errors`, `file_system`, `front_matter`,
  `highlight`, `init`, `luals`, `markdown`, `memory_file_system`, `navigation`, `page`, `reference`,
  `reference_site`, `search`, `site`, `system_file_system`, `internal/html`, `theme/init`, `theme/layout`,
  `theme/strings`), `theme.css`, `theme.js`, `theme-init.js`, the brand `LICENSE`, and `bin/build.lua`,
  `bin/reference.lua`.
- Tests, in full: every test file of `core`, `log`, `json`, `net`, `reactor` and `doc` (unit and integration:
  test names, strings, comments, expected messages), the fixtures of `reactor`, and the fixture sites, demo package
  and Markdown samples of `doc`; the READMEs of the fixtures.
- (e) `docs/spikes`, every text file: the 10 reports (OQ-1, 2, 3, 4, 5, 6, 8, 11, 39, 41, 44, 52), `README.md`,
  `OQ-8/` (`spike.lua`, `bench.lua`, `rp.c`, the patch, `luv-issue.md`, `luv-pr.md`), `OQ-44/churn.lua`, and
  `OQ-52/` (the five Lua scripts and the two spike crates).

Out of scope, on purpose (nothing else is unread): binary files (the PNG screenshots of
`docs/spikes/OQ-11-samples`, fonts, SVG brand files), vendored `packages/json/csrc/vendor/yyjson.*` (third-party,
`VENDORED.md`), `Cargo.lock` files and generated data (the golden pages and `export.json` of `doc`, the expected-output
tables `decode_cases.lua`, `encode_cases.lua` and `jcs_numbers.lua` of `json`, the PEM fixtures of `net`; their
headers and the vocabulary of their messages were checked).

### Findings

| # | Where | Defect | Fix | Status |
|---|---|---|---|---|
| F52 | `.github/dependabot.yml` | Only `packages/net/native` was watched; the crates of `json`, `doc` and the fuzz crate of `net` (each has a lockfile) were not. | `directories:` lists the four lockfile directories in the one `rust-crates` group of the existing entry (spike crates under `docs/spikes` excluded: historical). | fixed |
| F53 | `docs.yml`, `lychee.toml`, `nightly.yml` | "external links are checked nightly once nightly.yml exists": `nightly.yml` exists and has no link job; its header also promised "freshness of the pinned dependencies", which is no job of it. | Both say that the external link check is not written yet; `nightly.yml` header lists what it does. | fixed |
| F54 | `ci.yml` | Step names "Build native modules" and "Lint the native module" for the TLS module of `net` only (three native modules exist). | "Build the TLS native module", "Lint the TLS native module". | fixed |
| F55 | `native-code-reviewer` | Scope "C code under `packages/*/csrc`" although most native code is Rust (ADR 0021). | Scope and checklist cover `packages/*/native` and Rust (`unsafe`, `mlua` errors, clippy, locked dependencies). | fixed |
| F56 | `pkg-doc` | Allowed dependencies omitted `hecate.reactor`, which the README, the rockspec and `check-boundaries` list. | Added. | fixed |
| F57 | `translator-fr` | `check-translations` presented as existing (it is planned, Phase 3). | Marked as planned. | fixed |
| F58 | `orm` summary (README, `CLAUDE.md`, rockspec, catalogue, `llms.txt`, labels, agent) | "Data Mapper with Unit of Work, Identity Map" capitalised as proper names; the glossary terms are lower case (`data mapper`, `unit of work`, `identity map`). | Lower case everywhere the summary is repeated; generators report in step. | fixed |
| F59 | `tools/lib/glossary.lua` | The deny-list answers `spawn` with "fork" although the glossary now keeps `spawn` for an operating-system process (`reactor.spawn`). | The message says so and names the `glossary-ok` mark. | fixed |
| F60 | `tools/tests/glossary_test.lua` | Fixture `fork(task)` uses the discouraged "task" for a computation. | `fork(computation)`. | fixed |
| F61 | `tools/tasks/build_native.lua` | Comment "Windows builds go through LuaRocks" after the MSVC path (`build_c_windows`) was written. | Corrected. | fixed |
| F62 | `tools/README.md` | Layout omitted `tests/` and `cloud/`. | Added. | fixed |
| F63 | `packages/doc/native/src/lib.rs` | Doc comment lists the callout titles "note, tip, warning, caution, important" while the option key is `danger` (the theme name of the GFM `CAUTION` alert, ADR 0022). | Comment says `danger` (the GFM `CAUTION` alert). Comment only. | fixed |
| F64 | `packages/doc/src/hecate/doc/init.lua` | Header says the LuaLS code reference is not implemented; `luals`, `reference` and `reference_site` exist and the website build uses them. | Header lists it as implemented. | fixed |
| F65 | `packages/doc/src/hecate/doc/reference.lua` | Doc comment of `is_generated` described something else ("names of the generated pages ... stale-page check"). | Describes the marker test. | fixed |
| F66 | `packages/doc/README.md` | "Documented packages: core, reactor, net" while `DEFAULT_PACKAGES` is core, reactor, net, json, log. | Updated. | fixed |
| F67 | `theme.css` | Comment "Containers (callouts)": containers were superseded by GFM alerts (ADR 0022), and "container" is the dependency-injection term. | "Callouts (GFM alerts)". | fixed |
| F68 | `docs/spikes/OQ-8`, `OQ-39` | "the Proposed ADR 0023" and "ADR 0022 (Proposed)": both are Accepted. | Reworded. | fixed |
| F69 | `docs/spikes/OQ-5`, `OQ-52` | The OQ-5 addendum says a Lua encoder was chosen in ADR 0020 (it is `serde_json` now); OQ-52 refers to the pure-Lua reference encoder and fallback removed by OQ-53. | One italic note each, saying what was decided later; the measurements are untouched. | fixed |
| F70 | `pkg-orm` (description), `pkg-query` | The description of `pkg-orm` kept the capitalised "Data Mapper with Unit of Work, Identity Map" (F58 missed it); `pkg-query` said "the query builder" where the template and the other agents have no article. | Corrected; the template test now reproduces every agent byte for byte. | fixed |
| F71 | `tools` | `new-package` wrote a shorter agent than the 28 `pkg-*` files (no documents list, standards or invariants line), and `gen-rockspecs` rewrote a rockspec wholesale, erasing a hand-made `build` table. | `tools/lib/agent.lua` holds the template, used by `new-package` and checked against every agent by `tools/tests/agent_test.lua` (including a scaffold on a scratch repository); `tools/lib/rockspec.lua` keeps an edited `build` table, with `tools/tests/rockspec_test.lua`. | fixed |
| F72 | `packages/doc/.../reference.lua` | `alias_of` returned `class.short` on both branches of a condition. | Reduced to `class.short`, documented; tests pass. | fixed |
| F73 | `docs/spikes/OQ-39`, `docs/spikes/README.md` | comrak 0.56.0 measured against `0.52` pinned in `Cargo.toml`; no statement that spike scripts keep their period vocabulary. | One-line factual note in OQ-39; the policy stated once in the spikes README. | fixed |
| F74 | tests of `log`, `reactor`, `net`, `doc` | "task" for the drain computation (`test_close_flushes_stops_the_task...`, and the local `drain_task` of `async_sink.lua`, now `drain_future`); a local helper `spawn` that forks a coroutine (`tls_stream_test.lua`, now `fork_job`); "close handlers" for `__close` metamethods in test names and in `reactor/CLAUDE.md` ("handler" is reserved for I/O completion handlers); `ambient_test.lua` still named `ScopeLocalTest` and its first test spoke of a "reserved word name" (the second name that OQ-56 rules out); `test_write_to_a_reset_peer_raises_io_error` asserting a `TransportError`; "container titles" for callouts; a field named `handler` in a log test; French fixture "les scopes" (glossary: « portée »); "closed-trust path" in a TLS test comment. | Renamed or reworded; no behaviour changed. | fixed |
| F75 | specifications | `container`, `config` and `log` have only a few lines of specification (`overview.md`, two mentions of the container in `http-and-routing.md`), while their agents point to those files. | Not a vocabulary defect: recorded as OQ-62; owner decision 2026-10-26: `log` specified now in `docs/architecture/logging.md`, `container` and `config` when implemented (Phase 2). | `log` fixed; `container`, `config` deferred |

Observed and left, with the reason:

- Spike scripts and reports keep the vocabulary of their time ("handler" in `churn.lua`, "headers" in the llhttp
  report, "task" for tokio or Swift) and several refer to modules that no longer exist (`internal/reference.lua`,
  `backend.use`): history, stated once in `docs/spikes/README.md`; OQ-52 carries a dated note.
- The OQ-60 and OQ-61 renames (`level` to `severity` in `log`, `duplicate_key` to `duplicate_member_name` in `json`)
  were done by another agent while this pass ran; the tests read here already use the new names.
