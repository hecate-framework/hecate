# Phase 2 gate: `/review-package` findings

Read-only review of the Phase 2 packages (one reviewer agent per package, covering specification, layering, API,
vocabulary, tests, and security, portability and performance where relevant), run on 2026-11-13 at the head of
`claude/relay-phase-2-gate`: `http`, `kernel` with the meta-module `hecate`, `router`, `container`, `config`, and what
Phase 2 added to `reactor` (`offload`, the multi-process primitives). `schema` was reviewed on 2026-11-08
([schema-review-package.md](schema-review-package.md)) and is not reviewed again. Each finding carries its
disposition: fixed in the gate pull request (test first), or deferred to a named roadmap item or open question.

## container

| Id | Severity | Finding | Disposition |
|---|---|---|---|
| CT-1 | major | A constructor or factory that suspends is not detected (OQ-107 forbids it): the `_constructing[key]` flag is per container, so a second request in another service scope fails with a misleading `CycleError` (`db -> db`), and a construction closed while suspended leaves the flag set, so the key never resolves again (`container.lua:265-267`, `:311-314`). Reproduced. | Fixed, test first |
| CT-2 | major | (`kernel`) The service scope of a request is closed when `serve_matched` returns (`dispatcher.lua:141`), before a `Response` whose content is a function is written, which then uses closed scoped services; `container.md` says the scope ends with the request's reactor scope, under `shield` on cancellation. | Fixed, test first |
| CT-3 | minor | The "returned nil" `ConstructionError` has an empty `context.path`, and the `ConformanceError` of a factory product has none (`container.lua:278-283`). | Fixed, test first |
| CT-4 | minor | A closable factory product that fails the conformance check is never closed (`container.lua:281`). | Fixed, test first |
| CT-5 | minor | The same closable instance returned by a transient factory twice, or a singleton's instance returned by a transient factory, is tracked and closed twice (`container.lua:328-336`). | Fixed, test first |
| CT-6 | minor | The closable transients built for a singleton whose construction fails stay in `container._owned`, growing with every retry (`container.lua:323-325`). | Fixed, test first |
| CT-7 | minor | `override_with_instance` makes the container close an injected closable fake that the test still owns; `container.md` does not say who owns it (`container.lua:235`). | Deferred: OQ-123 (issue 189) |
| CT-8 | minor | `ServiceScope` can be constructed directly and then fails with a misleading "resolve before validate" (`container.lua:129`, `:404`). | Fixed, test first |
| CT-9 | minor | The property test accepts a `LifetimeError` for any non-scoped key at the root without checking it needs a scoped service; no closable products, interface keys or overrides are generated (`properties_test.lua:90-95`). | Fixed, test first |
| CT-10 | minor | No test for a failure partway through a graph inside a scope, a suspending constructor, or a resolution after a cancelled construction. | Fixed, test first |
| CT-11 | minor | The same captive dependency, reached directly and through a transient, is reported twice (`graph.lua:44-60`; by reading). | Fixed, test first |
| CT-12 | minor | Annotation nits: stray `--- ---` (`container.lua:352`); the description of `LifetimeError` omits the root refusal of a closable transient and `context.suppressed`; the message "instance must be a table" while a userdata is accepted (`container.lua:433`). | Fixed, test first |

## config

| Id | Severity | Finding | Disposition |
|---|---|---|---|
| CF-1 | major | `secrets` written as a map (`{ ["database.password"] = true }`) is accepted and protects nothing: `check_options` walks `ipairs` only, so `describe()` prints the password (`load.lua:93-95`, `:309`). Reproduced. | Fixed, test first |
| CF-2 | major | The `Configuration` object itself can be written (`configuration.get = ...`, `configuration._root = {}`), against "immutable after boot" (`configuration.lua:177`, `:184`). Reproduced. | Fixed, test first |
| CF-3 | minor | `describe()` renders a newline of a value with `%q` as a real line end, so an environment value can forge an extra line of the boot log (`configuration.lua:268-270`). Reproduced. | Fixed, test first |
| CF-4 | minor | `get` and `source` accept malformed paths (`get(".")` returns the root, `db..port` reads `db.port`) (`configuration.lua:197-202`). | Fixed, test first |
| CF-5 | minor | A property name containing `.` is accepted but can never be read nor named in `secrets` (`declaration.lua:68-78`, `:117`). | Fixed, test first |
| CF-6 | minor | `source()` of a section created only by environment variables or secret files says `schema default` (`load.lua:423-426`). | Fixed, test first |
| CF-7 | minor | OQ-110 (5) says `HECATE_ENV=""` is taken as unset; the code (and the specification) refuse it; no test. | Fixed: test added, OQ-110 (5) corrected |
| CF-8 | minor | `configuration.md:150-151` and the annotation at `load.lua:19` name two framework keys (`logging`, `limits`); `declaration.lua` reserves five. | Fixed (documentation) |
| CF-9 | minor | `config.variable_name` does not check its arguments (raw "attempt to concatenate a nil value") (`init.lua:36-38`). | Fixed, test first |
| CF-10 | minor | A non-string key or a mixed array/object in a configuration file is reported as `(root): expected object, got table` without the key or the file (`load.lua:151-180`, `:256-264`). | Fixed, test first |
| CF-11 | minor | The value of a secret object can be replaced (`secret._reveal = ...`), in `config` and in `log` (`secret.lua:18`). | Fixed, test first |
| CF-12 | minor | No size cap nor type check when reading a secret file: `/dev/zero` exhausts memory and a FIFO blocks the boot (`load.lua:102-110`, `:439`); a decision. | Deferred: OQ-124 (issue 190) |
| CF-13 | minor | On Windows `os.getenv` returns the ANSI code page, so a non-ASCII environment value may be misread (`load.lua:286`; not verified). | Deferred: OQ-124 (issue 190) |

## router

| Id | Severity | Finding | Disposition |
|---|---|---|---|
| R-1 | major | Overlapping affixed templates of the same text length (`/f/a{x}` and `/f/{y}b`) are accepted, and `/f/a1b` goes to one of them by byte order of the affixes, against "ambiguous route tables are rejected at boot" (`tree.lua:52-64`). Reproduced. | Fixed, test first (rejected when both routes serve one method and a path matches both) |
| R-2 | major | The specification says matching cost is independent of the number of routes; affixed siblings at a node are scanned one by one (a 404 costs 296 VM instructions with one `/f/{x}.e1` route, 160 424 with 10 000) (`http-and-routing.md:70`, `:83-84`; `tree.lua:135-150`). | Fixed (statement corrected, cost test added); indexing deferred to roadmap "Continuous" |
| R-3 | minor | A route list with a hole (`{r1, nil, r3}`) silently drops the routes after it (`router.lua:296`, `:305`; by reading). | Fixed, test first |
| R-4 | minor | `url_for` errors raised through `template.expand` name `url_for` and point inside `router.lua` (`template.lua:240`, `:243-249`, `:290`). | Fixed, test first |
| R-5 | minor | `template.parse(text)` and `path.split(raw)` without a policy behave as `strict`, not the documented default `ignore` (`template.lua:233`, `path.lua:116`). Reproduced. | Fixed, test first |
| R-6 | minor | `url_for` refuses an integer for a wildcard though the documentation says "strings or integers" (`template.lua:285`). Reproduced. | Fixed, test first |
| R-7 | minor | Under `trailing_slash = "strict"` a wildcard refuses a path ending with a slash; the guide does not say so (`tree.lua:93-101`). Reproduced. | Fixed (documented, test added) |

## reactor (Phase 2 additions)

The `-- coverage: off` region around the pool-thread body of `offload` was judged correct (only code that runs in
pool-thread states); RE-6 covers it with real tests.

| Id | Severity | Finding | Disposition |
|---|---|---|---|
| RE-1 | minor | `Peer:send` accepts a stream that has already been read: its buffered bytes are lost, and a running read-ahead can take bytes meant for the receiver (`ipc.lua:124-142`). No current caller is hit. | Fixed, test first (`ipc_test.lua`) |
| RE-2 | minor | Encoding errors of `offload` embed the path of table keys unescaped and uncut (a 1 MiB key gives a 1 MiB message; control characters reach the logs) (`transfer.lua:25-31`, `:54-56`, `offload.lua:222`). Reproduced. | Fixed, test first (`offload_test.lua`) |
| RE-3 | minor | A call cancelled while queued keeps its encoded arguments until the pool reaches it (`offload.lua:241-246`). | Fixed, test first (`offload_test.lua`) |
| RE-4 | minor | Garbage of a call stays in the pool thread's Lua state until that thread runs again (299 MB resident after one call building 3 million strings) (`offload.lua:35-79`). Reproduced. | Documented (`concurrency.md`, offload how-to); the collection step deferred to roadmap "Continuous" |
| RE-5 | minor | `OffloadError.context.reason = "worker"` collides with the glossary term *worker* (a process, ADR 0023) (`offload.lua:18`, `:75`; `concurrency.md:169`). | Deferred: OQ-125 (issue 191) |
| RE-6 | minor | No test for `require` on a pool thread, the `worker` reason, the `refused` path, or a function under its own `local _ENV`. | Fixed: tests added (`offload_test.lua`, `offload_exit_test.lua`) |
| RE-7 | minor | NUL bytes in `cwd` and in `env` names and values of `spawn` are not refused (luv cuts them) (`process.lua:268-283`). | Fixed, test first (`process_test.lua`) |
| RE-8 | minor | `supports_reuseport` caches any probe failure (EMFILE, no IPv4 loopback) as "unsupported" for the life of the process (`tcp.lua:597-611`). | Fixed, test first (`reuseport_test.lua`); an `ENOTSUP` probe is not cached either |
| RE-9 | minor | `pool_size()` maps a negative `UV_THREADPOOL_SIZE` to 1 where libuv reads 1024; the comment says "as libuv reads it" (`offload.lua:95-101`). | Fixed (comment; the safe behaviour is kept) |

## kernel and hecate

| Id | Severity | Finding | Disposition |
|---|---|---|---|
| K-1 | major | The ready watchdog of a generation is never cancelled when `ready` arrives; when a reload retires that worker (`old.ready = false`), the watchdog SIGKILLs it in the middle of its drain and logs `worker_not_ready`: any reload within `ready_timeout` of a worker's start kills it with requests in flight (`supervisor.lua:328-345`, `:614-618`; point (m)). Reproduced. | Fixed, test first |
| K-2 | major | `requests.inputs = "strict"` does not apply to a route that declares only `content`: `?undeclared=1` is accepted (`input.lua:252-253`; point (l)). Reproduced. | Fixed, test first |
| K-3 | major | The binding names of controller `dependencies` are resolved first at request time: a typo boots and every request answers 500, against "nothing validated lazily at first request" (`dispatcher.lua:36-56`); needs a public `Container:has(key)`. Reproduced. | Fixed, test first |
| K-4 | major | A worker that stops reading its message pipe stalls the hand-over to every worker under `round_robin`: `deliver` awaits `peer:send` inside the single accept loop (`listening.lua:290-338`, `supervisor.lua:249-258`). | Fixed, test first |
| K-5 | minor | Bad `server` options in a primary are validated only in each worker, so they become a crash loop instead of one boot error (`application.lua:476-481`). | Fixed, test first |
| K-6 | minor | `Accept: application/json;q=0, */*` still selects JSON; RFC 9110 section 12.5.1 gives 406 (`results.lua:61-77`, `:93-95`). | Fixed, test first |
| K-7 | minor | A problem for 405 or 401 cannot carry `Allow` or `WWW-Authenticate` (RFC 9110) (`problems.lua:114-136`). | Deferred: OQ-126 (issue 192) |
| K-8 | minor | The worker's drain is not counted in its grace period, so it races the primary's kill at `grace + 1` (`supervisor.lua:942-943`). | Fixed, test first |
| K-9 | minor | `on_crash_loop = "degrade"` ends `run` with `start_failed` when a restart cannot spawn (`supervisor.lua:314-319`). | Fixed, test first |
| K-10 | minor | Worker-side logs (`control_failed`, `hand_over_queue_full`, `hand_over_discarded`) go to `log.default()`, ignoring an explicit `logger` (`supervisor.lua:856`, `:865`, `:890`). | Fixed, test first |
| K-11 | minor | `developer-experience.md` annotates with `hecate.Controller` and `hecate.Request`, which do not exist; the `hecate` README says "schema shortcuts", against OQ-57. | Fixed, test first |
| K-12 | minor | No test that a worker survives `sigint` or `sigterm` sent to its own pid (OQ-116); stale "known defect ... Remove the skip" comments (`supervisor_test.lua:164-165`, `supervisor_reload_test.lua:206-207`). | Fixed, test first |
| K-13 | minor | "passes a connection to the worker" where the glossary term is hand-over (`listening.lua:25`). | Fixed |
| K-14 | minor | The `Accept` field is parsed into a sorted table on every request, even for `*/*` (`results.lua:61-114`). | Deferred: roadmap "Continuous" |
| K-15 | minor | An IPv6 link-local host with a zone id (`fe80::1%eth0`) is bound by the primary but refused by every worker, which then crash-loop (`supervisor.lua:54-58`). | Fixed, test first |

## http

| Id | Severity | Finding | Disposition |
|---|---|---|---|
| H-1 | blocker | Quadratic trimming of field values (`^[ \t]*(.-)[ \t]*$`) lets one client stall the reactor thread within the default limits: a 56 KiB head of seven whitespace-heavy fields costs 1.56 s in `Parser:feed`; three such requests delayed a plain `GET` on another connection by 4.9 s (`fields.lua:53`, `:66`; `server_connection.lua:180`; `wire.lua:64`; `cookie.lua:102`). Reproduced. | Fixed, test first |
| H-2 | major | `native.new(kind)` called with one argument runs `lua_next` on the userdata it just pushed (undefined behaviour in C; not reachable from the network) (`csrc/native.c:520-531`). Reproduced. | Fixed, test first |
| H-3 | major | 94 % of parse time is `Fields:add` re-validating what llhttp already checked in strict mode (61 µs per 18-field head against 3.9 µs) (`parser.lua:93-96`). | Fixed, test first |
| H-4 | minor | `shutdown` closes without an answer a connection whose request head has partly arrived (`server.lua:275-276`). Reproduced. | Fixed, test first |
| H-5 | minor | An HTTP/1.0 request with several `Host` lines is served and no value is validated (`server_connection.lua:158-165`). Reproduced. | Fixed, test first |
| H-6 | minor | `GET *` (asterisk-form outside OPTIONS) and an origin-form target with a fragment (`/a#x`) are served (`server_connection.lua:156-187`, `request.lua:53`). Reproduced. | Fixed, test first |
| H-7 | minor | A 205 response may carry content, against RFC 9110 section 15.3.6 (`status.lua:57`). | Fixed, test first |
| H-8 | minor | A comment of the native binding says a Lua memory error cannot leave a parser that is not failed; on the success path it can (`csrc/native.c:14`, `:713`). | Fixed (a failure is stored on the success path too; sanitizer run) |
| H-9 | minor | "Header block of a part" in the README, where the glossary and OQ-75 say header fields (README:100). | Fixed, test first |

## Found while closing the findings

| Id | Severity | Finding | Disposition |
|---|---|---|---|
| L-1 | minor | `leaks kernel` fails on `main` too: `test_sigint_shuts_the_server_down_gracefully` and `test_an_expired_deadline_gives_a_500_and_the_server_record_without_traceback` (`application_test.lua`) each leave one `uv_tcp_t` open; the nightly `leaks` job checks `reactor` and `net` only. The tests now close their `http.Client`, which was not the cause. | Fixed: the tests left their response unread, so it held its connection; `kernel` added to the nightly `leaks` job |
| L-2 | minor | The French guide `website/fr/how-to/route-requests.md` does not carry the router changes (R-1, R-2, R-7). | Deferred: the French translation sync (roadmap "Continuous"; `check-translations`, Phase 3) |
