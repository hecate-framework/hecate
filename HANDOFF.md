<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `router`: radix tree, URI template subset, 404/405, reverse routing (+ percent-decode segments, dot segments; OQ-75)
- status: in-progress            <!-- in-progress | waiting-ci | waiting-owner -->
- lock_until: 2026-11-01T23:26:57Z
- last_update: 2026-11-01T21:56:57Z

## Done

- Step 1: `hecate.router.path` (split with percent-decoding per segment and dot segments, encode/decode) and
  `hecate.router.template` (parse the level-1 subset plus `{name...}` wildcard, expand for reverse routing), tests first
  (`tests/unit/path_test.lua`, `template_test.lua`). typecheck, lint, tests clean.

## Next steps

2. `tree.lua` + `router.lua` (class `Router(routes, options)`: `match(method, path)` -> `Match` with status 200/204/404/405,
   `allow`; `url_for`; `routes()`; `route(name)`), boot-time ambiguity diagnostics (`RouteTableError`), `init.lua`; tests first
   (match precedence, backtracking, 405/Allow, automatic HEAD/OPTIONS, trailing slash policy, ambiguity, instruction-count
   test for the static-prefix invariant, property tests with generated route sets).
3. Docs: README (status, Public API), website reference page + how-to (with tested examples in `examples/`), CHANGELOG
   `[Unreleased]`, open questions (see doubts), `benchmarks/match.lua`, glossary entries if needed
   (path template, path parameter, wildcard), architecture spec update. Run check-* tasks. Roadmap tick only at the very end.

## Decisions taken (and where they are recorded)

- Tree is a trie over decoded segments (radix over segments); parameters are bound by position, names per route.
- Strict trailing slash by default (`/a` and `/a/` differ); `ignore` option drops one trailing empty segment of path and template.
- To record in `docs/open-questions.md` (step 3): see doubts.

## Doubts and questions for the owner

- Mixed segments (`/{id}.json`) refused (the spec says whole-segment parameters).
- `%00` and malformed percent-encoding answer 400; wildcard never matches a segment whose decoded text holds `/` (so it
  cannot smuggle `..%2F`); `//` empty segments never match a parameter.
- `url_for` raises on unknown names, unknown parameters, `.`/`..`/empty values.
- `%2e` is treated as a dot segment (RFC 3986 section 6.2.2.2).

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
lua tools/run.lua test router
lua tools/run.lua lint
```
