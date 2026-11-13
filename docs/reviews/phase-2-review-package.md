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
