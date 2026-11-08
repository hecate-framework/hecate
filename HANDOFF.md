<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `schema`: refinement types, composition, coercion, validation with JSON Pointer error paths, JSON Schema 2020-12 emission.
- status: waiting-owner          <!-- in-progress | waiting-ci | waiting-owner -->
- lock_until: 2026-11-08T12:17:24Z
- last_update: 2026-11-08T08:17:24Z

## Done

- Step 1 (type model and validation core): `packages/schema/src/hecate/schema/{init,schema,violation}.lua`, tests in `packages/schema/tests/unit/validate_test.lua`. Types: string, integer, number, boolean, literal, enumeration, object, array, optional, nullable, union; `validate` collects all violations with JSON Pointer paths, `check` raises `ValidationError`. Schemas are value classes (immutable), validators compiled at declaration. README status, CHANGELOG, OQ-85 updated. typecheck, lint, test schema, check-boundaries pass.

- Step 2a (JSON Schema emission of the current types): `Schema:to_json_schema()` in `schema.lua`, tests in `packages/schema/tests/unit/emit_test.lua` (structural unit tests plus differential tests against an independent checker of the emitted keywords). OQ-85 points 10 to 13 (pattern refused, `1.0` gap documented, shapes of `nullable`/`optional`, `json.null` no longer an array/object). README and CHANGELOG updated.

- Step 3 (coercion): `Schema:coerce` with compiled `coercer` closures, tests in `packages/schema/tests/unit/coerce_test.lua`, OQ-85 points 14 to 17, README and CHANGELOG updated. typecheck, lint, test schema pass (needs `build-native json`).

- Step 2b-1: `exclusive_minimum`/`exclusive_maximum` on integer and number, `unique_items` on array (validation, emission, differential tests). Needs `lua tools/run.lua build-native json` before `test schema`.

- Step 2b-2 (`pattern` translator): spec section "The `pattern` option" in `schemas-and-contracts.md`, `packages/schema/src/hecate/schema/pattern.lua`, tests `pattern_test.lua` (incl. differential matcher), emission uses it, OQ-86 added. The declaration-time warning of OQ-85 is implemented as an optional duck-typed `logger` option of `schema.string` (no `log` dependency: check-boundaries allows only core and json). Rebased on the other relays' steps 2b-3 to 2b-5. typecheck, lint, test schema, check-boundaries, check-glossary pass.

- Step 2b-3: `map` and `multiple_of` (validation, coercion, emission, differential tests), OQ-87 added (mirror issue still to create). typecheck, lint, test schema pass.

- Step 2b-4: `tagged_union` and `default` (validation, coercion, emission, differential tests), OQ-88 added (mirror issue still to create from the template). typecheck, lint, test schema pass.

- Step 2b-5: `named` (`$defs`/`$ref`), `any`, `null`; OQ-89 added (mirror issue still to create). typecheck, lint, test schema pass.

- Step 2b-6: `format` option of `string` (uuid, date, date-time, email); typecheck, lint, test schema pass. Further formats (uri, ...) not done.

- Step 2b-7: `ipv4` format (validation, emission passes through); typecheck, lint, test schema pass.

- Docs step: `website/en/how-to/validate-with-schemas.md` with two tested examples (`packages/schema/examples/`, `examples_test.lua`), reference index entry, `schema` in `DEFAULT_PACKAGES`. typecheck, lint, test schema, check-docs-examples, check-links pass. French page (translator-fr) and generated reference pages not done (`test doc` needs `build-native doc`, Rust).

- Step 4a: `schema.of(Class|module name)` (lazy memoized, cycles via `$ref`; tests `of_test.lua`: self, mutual, 3-cycle, lazy, refusal). typecheck, lint, test schema, check-boundaries pass.

- Step 4b: `Schema:build(content,{method})` (instances of class-bound parts, absent = nil, PATCH relaxed top-level), `schema.sent`, tests `build_test.lua`, OQ-90 (presence set stored under a private non-string key because raw setmetatable is reserved to core; `Class()` must accept no argument). Mirror issue for OQ-90 is #143. typecheck, lint, test schema pass.

- CI fix: markdownlint failed on the OQ-90 row of `docs/open-questions.md` (missing last cell); fixed. Run `npx markdownlint-cli2 "**/*.md" "#spikes" "#.hecate"` before pushing docs.

- Run 2026-11-04 06:50Z: resumed after lock expiry; CI green on the three platforms; created mirror issue #143 for OQ-90. No code change (toolchain not built in this session: `.hecate/toolchain` absent).

- Run 2026-11-04 09:45Z: toolchain rebuilt, `test schema` green. Verified that `json.encode` refuses an instance holding the presence key (EncodeError); recorded in OQ-90 (owner choice: encoder rule or side table), not decided. Decided 2026-11-07 (OQ-90 resolved): the presence set moves to a weak-keyed side table behind a new `core` helper for weak tables (so the encoder needs no change), and a class-bound instance is allocated without `init` through one `core` allocation function that calls `setmetatable`.
- Core step (OQ-90): `core.allocate(class)` (instance without `init`, the only `setmetatable` for instances; ArgumentError for a non-class or a `value_class`, ConformanceError for a class not finalised, like `Class()`) and `core.weak_table(mode?)` ("k" default, "v", "kv"), tests `packages/core/tests/unit/allocate_test.lua`, README, object-model.md, CHANGELOG. typecheck, lint, check-annotations, check-boundaries, check-glossary, check-changelog, check-links, test core pass; markdownlint-cli2 not available offline.
- Schema switch (OQ-90): `Schema:build` uses `core.allocate`, presence set in `core.weak_table("k")` side table, tests in `build_test.lua` (init with arguments, pairs, json.encode, weak liveness, sent on foreign values), README and CHANGELOG updated.

- Depth check (OQ-50): verified with `deep_test.lua` that a recursive schema validates, coerces and builds a decoded tree of exactly 1000 levels, that `json.decode` refuses 1001 levels before `schema` sees them, and that a hand-built table of 200000 levels would exhaust memory without a guard; added a 1000-level nesting guard (`depth_limit` violation with the JSON Pointer where it stopped) in the container validators and coercers.

- OQ-91 (security): `union_cost_test.lua`; fail-fast alternatives with literal properties first, lazy `context.alternatives` for the outermost failed union, work budget `complexity_limit` (1,000,000 steps, shared by validate, coerce and build, reset on entry), literal prefilter for union coercion and build. Measured before/after: depth 13 0.339 s then 0.002 s; depth 1000 validate 0.15 s, coerce 0.02 s, build 0.02 s; depth 20 was out of memory. No schema benchmark exists yet (step 4 of next steps).

- OQ-91 memoisation (option b, confirmed by the owner): a `union` memoises, within one `validate`, `coerce` or `build` call, its validation verdict and its coerced value per table node (cache created on first union visit, dropped by `reset_work`, nothing stored once the budget is spent; non-union schemas never touch it). Measured on two classes of identical shape, `next = optional(union(P, Q))`, invalid innermost value: before, depth 12 0.002 s and depth 20 to 30 about 0.4 to 0.7 s ending in `complexity_limit` (budget), depth 1000 0.85 s with `complexity_limit`; after, depth 30 0.0004 s and depth 1000 0.009 s, a `union` violation with no `complexity_limit`. Tests in `union_cost_test.lua`: linear cost for validate, coerce and build (below 0.05 s at depths 30 and 1000, fail before the change), identical violations, paths and top-level-only `context.alternatives` (checked equal on the revision before the change at depth 12), shared nodes and no stale cache across calls, failed `coerce` shape. Failed `coerce` shape check against `b67dfde^`: no real difference. A plain union (including objects with literal tags) reports one `union` violation at the union path with the alternatives, as before; only `tagged_union` reports the selected variant (OQ-88 point 2, as the owner's wording of the task suggested for literal-tag unions, but that rule belongs to `tagged_union`, not to a plain `union`). The two budget tests now lower `max_steps` to 100 because the old adversarial schema is linear.

- Step 4c (OQ-88): `Schema:build` applies `default` for JSON content except PATCH (fresh deep copy, null stays null, `schema.sent` false for defaulted attributes, nested, unions, class-bound, top-level default); tests `defaults_build_test.lua`; README, architecture, how-to, CHANGELOG.

- Step OQ-89 (names): the collision error of `to_json_schema` says where each name comes from (class or `named`); tests in `named_test.lua`; README, architecture, how-to and CHANGELOG present classes as primary and `named` as the inline-DTO opt-in.

- Step 6 (benchmark): `packages/schema/benchmarks/validate.lua` (`bench schema/validate`), CHANGELOG. Measured on this VM: validate record ~470k/s, array of 100 ~4.4k/s, union ~580k/s; coerce about half. Numbers to be published by the owner on dedicated hardware.

- Step 2b-8 (run 2026-11-08 06:42Z): `uri` format (RFC 3986 with scheme, conservative); typecheck, lint, test schema, check-changelog pass. Remaining formats: none planned beyond `uri`.

- Run 2026-11-08 08:15Z (resumed after lock expiry; CI green on the three platforms; json native built, `test schema` green). No code change: the remaining items (`value_class` binding, coerce-then-build, official JSON Schema test suite) have no specification text, so inventing them would deviate from CLAUDE.md. Owner: please say whether the schema item may be ticked as is (deferring these three to new roadmap items) or give the intended semantics.

## Owner-driven session

The owner asked on 2026-11-08 to finish this pull request the same day; an interactive session holds the lock until `lock_until` and drives the remaining steps, then releases it. A relay run must skip this pull request while the lock is in the future.

## Next steps

1. (DONE 2026-11-07, run 21:41Z: refusal, tests, architecture note, CHANGELOG; how-to note not added) OQ-87 resolved: refuse a non-integer `multiple_of` at declaration (clear message, tests, emission unchanged for integers); document why in the schema reference and the how-to, with the alternatives: integers in minor units, or a string with a `pattern` for a fixed number of decimals (JSON Schema has no keyword for decimal places), and a future decimal type.
2. (DONE 2026-11-08: `json.DEFAULT_MAX_DEPTH`/`MAX_DEPTH_CEILING` exposed, schema reads it; typecheck, lint, test schema/json pass) OQ-92 resolved: `schema` reads its depth guard default and ceiling from `json` (expose the cap and default in `hecate.json` if not already, then replace the constant in `schema.lua`; the work budget of OQ-91 stays a separate internal constant). The `limits.max_depth` configuration key belongs to the kernel item.
3. (2b) Remaining emission work: official JSON Schema test suite (supported subset), the `1.0` gap is confirmed; (pattern translator done); more formats (uri), core enumeration support, recursive schemas (named done).
4. Class-bound schemas, remaining: `value_class`, coerce-then-build. (Done: interface, sent, PATCH, construction, `core.allocate` and weak side table switch.)
5. Docs: website pages, tested examples, glossary check, reference generation (`DEFAULT_PACKAGES`).
6. (DONE 2026-11-08) Benchmarks for compiled validators.

## Open question issues

- Every entry of `docs/open-questions.md` has a mirror issue (labels `open-question`, `oq:*`, `package:*`; see the note at the top of the file and `.github/ISSUE_TEMPLATE/open-question.md`). When this branch adds an open question (for example for the `pattern` translator), create its issue from the template, never with `needs-decision` or `blocked`. OQ-85 is #131 (closed). The template and labels reach `main` with this pull request.

- OQ-86 resolved (2026-11-07): the declaration warning falls back to `log.default()` only when `hecate.log` is already in `package.loaded` (no dependency on `log`); implement this fallback in `schema.string` when `log.default()` exists (kernel first step); until then only the `logger` option works.

## Decisions taken (and where they are recorded)

- Validation-core choices (Lua pattern, `integer` refuses 1.0, nullable is json.null only, union is anyOf, ...): OQ-85.

## Doubts and questions for the owner

- None open for the owner on this item. The questions OQ-85 to OQ-92 are all resolved (rows in the Resolved table of `docs/open-questions.md`, mirror issues closed); the remaining open questions belong to other packages and must not be resolved by this run.

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
