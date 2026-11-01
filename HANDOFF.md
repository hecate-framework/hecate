<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `router`: radix tree, URI template subset, 404/405, reverse routing (+ percent-decode segments, dot segments; OQ-75)
- status: waiting-ci            <!-- in-progress | waiting-owner | waiting-ci -->
- lock_until: 2026-11-01T23:37:38Z
- last_update: 2026-11-01T22:07:38Z

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

1. Follow CI on the three platforms of the draft PR; fix failures.
2. Run the reviewers (`/review-package router`: architect, terminology, api, test-engineer, security, performance), triage.
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
