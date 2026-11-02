<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `router`: radix tree, URI template subset, 404/405, reverse routing (+ percent-decode segments, dot segments; OQ-75)
- status: in-progress
- lock_until: 2026-11-02T07:00:00Z
- last_update: 2026-11-02T06:50:00Z

## Done

- Step 1: `hecate.router.path` and `hecate.router.template`, tests first.
- Step 2: `Router` (match 200/204/400/404/405, Allow, automatic HEAD/OPTIONS, trailing_slash policy, url_for, routes(), route()),
  `RouteTableError`, tree with backtracking, oracle property tests, instruction-count test of the static-prefix invariant.
- Step 3: docs. README (status, Public API, layout), guide `website/en/how-to/route-requests.md` (+ OUTLINE, how-to index,
  reference index), tested examples (`packages/router/examples/`, `tests/unit/examples_test.lua`), CHANGELOG `[Unreleased]`,
  OQ-83 (choices to confirm), glossary rows (path template, route table, dot segment), spec "Implemented surface",
  `benchmarks/match.lua`, `gen-catalogue` and `gen-llms-txt` run.
- Cross-package one-word edits (as `http` did): `packages/doc/src/hecate/doc/reference_site.lua` DEFAULT_PACKAGES and
  `.github/workflows/website.yml` reference check now list `router`.

## Next steps

1. CI green on 3 platforms (checked 2026-11-02). Reviews running (step 4).
2. (DONE: api + security reviews, triage below; test-engineer, performance, terminology, architect not yet run) Run the reviewers (`/review-package router`: architect, terminology, api, test-engineer, security, performance), triage.
3. `translator-fr`: French page of `how-to/route-requests.md` and the reference index line (not done here).
4. Only when CI is green and reviews are triaged: tick the roadmap item, delete this file, mark the PR ready.

## Decisions taken (and where they are recorded)

- All undecided choices: OQ-83 in `docs/open-questions.md` (whole-segment parameters, wildcard rules, 400 for unreadable
  paths, `%2E` as dot, strict trailing slash, automatic HEAD/OPTIONS, method fallback, `url_for` strictness).

## Doubts and questions for the owner

- See OQ-83. Notably: status 400 vs 404 for malformed percent-encoding, and `Allow` as the union over all matched routes.
- `lua tools/run.lua test doc` cannot run here (native `hecate.doc.native` not built, needs Rust); the `doc` edit is only a list entry.
- `check-changelog` needs the commit (it reads the diff against the base).

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
lua tools/run.lua test router
lua tools/run.lua lint
lua tools/run.lua check-docs-examples
lua tools/run.lua check-links
lua tools/run.lua check-changelog
lua packages/router/benchmarks/match.lua
```

## Review triage (2026-11-02, api-reviewer + security-reviewer, report-only; none major)

To FIX in this PR (test first), next run:
- Error stack levels point inside router (router.lua:46,52; template.lua:88): fix levels + test position.
- `Router:route(name)` lacks string check (router.lua:221); `routes` as map silently empty (router.lua:85,104): raise RouteTableError/ArgumentError.
- Wording: `Match.route` is "the route as declared" (router.lua:30, 209); soften spec line "cost proportional to path length" to "bounded by longest template" (docs/architecture/http-and-routing.md).
- Document return-vs-raise split of path/template modules; document `Match.status` meaning; README warning that `{id}` accepts decoded `/` and `\`, wildcard rejects `/` (file-serving handlers must root-resolve, reject `\`, `:`).
- Tests to add: `%2e` last segment with trailing_slash=ignore; `{id}` accepting `..%2F..`; `%5C`, `%0D%0A` pass-through; mixed-case `%2E%2e` via match; 405/204 path uses dot-segment resolution; adversarial backtracking table; very long path / many segments; float/table values in url_for wildcard; decode(encode(x))==x property.

To DEFER (record in OQ-83 as limits/candidates, owner to confirm):
- Input limits (max_segments, template length/route count caps): http layer bounds request line; candidate router option.
- Option `reject_encoded_slash`; expose resolved path on `Match` (OQ-75 raw/resolved divergence for middleware).
- `allow_field` redundant with `allow`; `route()` vs `routes()` naming; option-style consistency.

## Update 2026-11-02 (resume run)

Fixed with tests: `route(name)` type check, `routes` map rejected, `Match.route` wording, spec wording, README handler warning,
pass-through and long-path tests. Stack levels: table errors take no position and the traceback skips only core frames, so
nothing to fix (recorded in OQ-83). Deferred items recorded in OQ-83. Reviews done and triaged (architect, terminology, test, performance; fixes pushed, rest in OQ-83 and the roadmap benchmark item). Still to do (old line): test-engineer, performance, terminology,
architect reviews; French page (`translator-fr`); then tick, delete this file, ready for review.

## Update (French page)

`website/fr/how-to/route-requests.md` and the two French index lines are done. Remaining: add path template, route table,
dot segment, trailing slash to `website/fr/glossary-terms.md`; wait for CI green on 3 platforms; then tick the roadmap item,
delete this file, mark ready, ask for review.

## Update (French glossary)

French glossary terms added and pushed. Only remaining: confirm CI green on 3 platforms for the latest commit (no check runs
were reported yet at 06:50Z), then tick the roadmap item, delete this file, mark ready, ask the owner for review.
