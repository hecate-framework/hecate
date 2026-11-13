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
| CT-1 | major | A constructor or factory that suspends is not detected (OQ-107 forbids it): the `_constructing[key]` flag is per container, so a second request in another service scope fails with a misleading `CycleError` (`db -> db`), and a construction closed while suspended leaves the flag set, so the key never resolves again (`container.lua:265-267`, `:311-314`). Reproduced. | Open |
| CT-2 | major | (`kernel`) The service scope of a request is closed when `serve_matched` returns (`dispatcher.lua:141`), before a `Response` whose content is a function is written, which then uses closed scoped services; `container.md` says the scope ends with the request's reactor scope, under `shield` on cancellation. | Open |
| CT-3 | minor | The "returned nil" `ConstructionError` has an empty `context.path`, and the `ConformanceError` of a factory product has none (`container.lua:278-283`). | Open |
| CT-4 | minor | A closable factory product that fails the conformance check is never closed (`container.lua:281`). | Open |
| CT-5 | minor | The same closable instance returned by a transient factory twice, or a singleton's instance returned by a transient factory, is tracked and closed twice (`container.lua:328-336`). | Open |
| CT-6 | minor | The closable transients built for a singleton whose construction fails stay in `container._owned`, growing with every retry (`container.lua:323-325`). | Open |
| CT-7 | minor | `override_with_instance` makes the container close an injected closable fake that the test still owns; `container.md` does not say who owns it (`container.lua:235`). | Open (missing decision) |
| CT-8 | minor | `ServiceScope` can be constructed directly and then fails with a misleading "resolve before validate" (`container.lua:129`, `:404`). | Open |
| CT-9 | minor | The property test accepts a `LifetimeError` for any non-scoped key at the root without checking it needs a scoped service; no closable products, interface keys or overrides are generated (`properties_test.lua:90-95`). | Open |
| CT-10 | minor | No test for a failure partway through a graph inside a scope, a suspending constructor, or a resolution after a cancelled construction. | Open |
| CT-11 | minor | The same captive dependency, reached directly and through a transient, is reported twice (`graph.lua:44-60`; by reading). | Open |
| CT-12 | minor | Annotation nits: stray `--- ---` (`container.lua:352`); the description of `LifetimeError` omits the root refusal of a closable transient and `context.suppressed`; the message "instance must be a table" while a userdata is accepted (`container.lua:433`). | Open |

## config

| Id | Severity | Finding | Disposition |
|---|---|---|---|
| CF-1 | major | `secrets` written as a map (`{ ["database.password"] = true }`) is accepted and protects nothing: `check_options` walks `ipairs` only, so `describe()` prints the password (`load.lua:93-95`, `:309`). Reproduced. | Open |
| CF-2 | major | The `Configuration` object itself can be written (`configuration.get = ...`, `configuration._root = {}`), against "immutable after boot" (`configuration.lua:177`, `:184`). Reproduced. | Open |
| CF-3 | minor | `describe()` renders a newline of a value with `%q` as a real line end, so an environment value can forge an extra line of the boot log (`configuration.lua:268-270`). Reproduced. | Open |
| CF-4 | minor | `get` and `source` accept malformed paths (`get(".")` returns the root, `db..port` reads `db.port`) (`configuration.lua:197-202`). | Open |
| CF-5 | minor | A property name containing `.` is accepted but can never be read nor named in `secrets` (`declaration.lua:68-78`, `:117`). | Open |
| CF-6 | minor | `source()` of a section created only by environment variables or secret files says `schema default` (`load.lua:423-426`). | Open |
| CF-7 | minor | OQ-110 (5) says `HECATE_ENV=""` is taken as unset; the code (and the specification) refuse it; no test. | Open |
| CF-8 | minor | `configuration.md:150-151` and the annotation at `load.lua:19` name two framework keys (`logging`, `limits`); `declaration.lua` reserves five. | Open |
| CF-9 | minor | `config.variable_name` does not check its arguments (raw "attempt to concatenate a nil value") (`init.lua:36-38`). | Open |
| CF-10 | minor | A non-string key or a mixed array/object in a configuration file is reported as `(root): expected object, got table` without the key or the file (`load.lua:151-180`, `:256-264`). | Open |
| CF-11 | minor | The value of a secret object can be replaced (`secret._reveal = ...`), in `config` and in `log` (`secret.lua:18`). | Open |
| CF-12 | minor | No size cap nor type check when reading a secret file: `/dev/zero` exhausts memory and a FIFO blocks the boot (`load.lua:102-110`, `:439`); a decision. | Open (missing decision) |
| CF-13 | minor | On Windows `os.getenv` returns the ANSI code page, so a non-ASCII environment value may be misread (`load.lua:286`; not verified). | Open (missing decision) |

## router

| Id | Severity | Finding | Disposition |
|---|---|---|---|
| R-1 | major | Overlapping affixed templates of the same text length (`/f/a{x}` and `/f/{y}b`) are accepted, and `/f/a1b` goes to one of them by byte order of the affixes, against "ambiguous route tables are rejected at boot" (`tree.lua:52-64`). Reproduced. | Open |
| R-2 | major | The specification says matching cost is independent of the number of routes; affixed siblings at a node are scanned one by one (a 404 costs 296 VM instructions with one `/f/{x}.e1` route, 160 424 with 10 000) (`http-and-routing.md:70`, `:83-84`; `tree.lua:135-150`). | Open: correct the statement and test the static case in the gate; indexing affixed siblings deferred |
| R-3 | minor | A route list with a hole (`{r1, nil, r3}`) silently drops the routes after it (`router.lua:296`, `:305`; by reading). | Open |
| R-4 | minor | `url_for` errors raised through `template.expand` name `url_for` and point inside `router.lua` (`template.lua:240`, `:243-249`, `:290`). | Open |
| R-5 | minor | `template.parse(text)` and `path.split(raw)` without a policy behave as `strict`, not the documented default `ignore` (`template.lua:233`, `path.lua:116`). Reproduced. | Open |
| R-6 | minor | `url_for` refuses an integer for a wildcard though the documentation says "strings or integers" (`template.lua:285`). Reproduced. | Open |
| R-7 | minor | Under `trailing_slash = "strict"` a wildcard refuses a path ending with a slash; the guide does not say so (`tree.lua:93-101`). Reproduced. | Open |
