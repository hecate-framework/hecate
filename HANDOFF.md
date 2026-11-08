<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `schema`: refinement types, composition, coercion, validation with JSON Pointer error paths, JSON Schema 2020-12 emission.
- status: in-progress            <!-- in-progress | waiting-ci | waiting-owner -->
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

- Steps 1 and 2 of OQ-93 (owner-driven session): `core.instantiate_value(class, fields)` (frozen instance of a value class from a table of attributes, no `init`; `ArgumentError` for a non-value-class or non-table, `ConformanceError` if not finalised, table copied) and `core.is_value_class(class)`, tests in `allocate_test.lua`; `Schema:build` uses it for class-bound parts whose class is a value class (`value_build_test.lua`); `Schema:build(content, { method, coerce = true })` converts texts then builds, defaults once, `sent` only for provided attributes, PATCH without defaults (`coerce_build_test.lua`); READMEs, object-model, schemas-and-contracts, how-to, CHANGELOG updated.

- Next step 3 (official JSON Schema test suite): `tests/external.lua` pins JSON-Schema-Test-Suite at 245a45a (2026-11-08, MIT), `json_schema_suite_test.lua` with an explicit skip table, shared checker moved to `tests/support/conforms.lua` (deep equality, `$ref`, `type` arrays), CI and nightly download it. Real bug found and fixed: `object` and `map` accepted a decoded array, `array` accepted a decoded object (`validate_test.lua`). Doubt: the `1.0` and fractional `multipleOf` cases are counted as documented gaps only when Lua disagrees and the data or schema holds the trigger.
- The review findings of OQ-94 were fixed (the value raised by `__pairs` or its iterator is raised again as the same value; one shared entry budget per encode).
- Docs step (English, owner-driven session): tested examples in `packages/schema/examples/` (`string`, `integer` with `multiple_of`, `map`, `enumeration`, `tagged_union`, `of`, `Schema.build`, `default`, `sent`) run and asserted by `examples_test.lua`; the how-to `validate-with-schemas.md` reorganised (validate, constrain, name, build, defaults and PATCH, emit); new explanation page `website/en/explanation/schemas-and-contracts.md`; glossary rows violation, class-bound schema, presence set, work budget (in `docs/glossary.md` only, like the router item; the public copy `website/en/reference/glossary.md` is not updated); README status; CHANGELOG. The generated reference pages are not built here.

- Step OQ-95 (owner-driven session): `Schema:represent(value)` in `schema.lua` (compiled `representer` closure per schema, made at declaration like the validators, wrapped by the shared depth guard and work budget; `reset_work` on entry), tests `represent_test.lua`, example `hecate.schema.Schema.represent`, README, architecture, how-to, explanation page, CHANGELOG. Errors are `ValidationError` with one violation in `context.violations`, as `check` does.

- French mirror of the schema pages (translator-fr): `website/fr/how-to/validate-with-schemas.md` and `website/fr/explanation/schemas-and-contracts.md` (examples copied verbatim under the same markers), links added to the French how-to, explanation and reference indexes, terms in `website/fr/glossary-terms.md` only. `source_revision` is the full hash of the last commit of the English page (135eb4535b8734db2bc5ef6c3f7faf77ac8299ea for both pages; the indexes carry the last commit of their English index), as the router item did. No CHANGELOG line (the router item had none for its French page). check-glossary, check-links, check-docs-examples, check-changelog, lint, typecheck pass.

## Doubts (OQ-95, conservative choices taken)

- The name `represent` is kept: the glossary defines the term representation (Fielding, RFC 9110), and the specification speaks of representations.
- A built attribute that was an explicit `null` is nil in the instance (OQ-90), so `represent` omits it, and the rebuilt content then fails `required` for a nullable attribute that is not optional. Only an attribute set to `json.null` by hand is represented as null. If a round trip of explicit nulls matters, an owner decision is needed (for example keeping `json.null` in the instance, or using the presence set).
- A union first tries the alternatives on the value as it is (linear, memoised), and only if none accepts it represents it with each alternative and validates the plain result (needed when an instance holds an enumeration member, which the alternative's validator only accepts as a name). That second pass is bounded by the work budget, not memoised per alternative.
- A value of the wrong shape (not a table for an object, array or map), an unknown tag, a non-member for an enumeration and an unmatched union raise `ValidationError` (codes `type`, `tagged_union`, `enum`, `union`) instead of producing garbage.
- Map keys that are not strings are copied as they are (the encoder then refuses them); `any` deep-copies and keeps the markers, and stops at the depth guard.

## Doubts (French mirror)

- French renderings chosen conservatively, listed in `website/fr/glossary-terms.md`: violation, schéma lié à une classe, ensemble de présence, budget de travail, unités mineures, « à échec rapide », objet de transfert de données. The public French glossary page is not updated (the English one is not either).
- The French indexes carry the English index revision although they do not list the untranslated HTTP pages.

## Owner-driven session

The owner asked on 2026-11-08 to finish this pull request the same day; an interactive session holds the lock until `lock_until` and drives the remaining steps, then releases it. A relay run must skip this pull request while the lock is in the future.

## Next steps

1. DONE OQ-94, decided by the owner: the native JSON encoder honours `__pairs` for tables that define one (frozen `value_class` instances encode as their attributes; today `json.encode` writes `{}` silently); tests first, native-code-reviewer, benchmark of the plain path; then switch the value instance encode test in `packages/schema/tests/unit/value_build_test.lua` from the `pairs` copy to a direct `json.encode` of the built instance.
2. DONE OQ-93 (1), decided by the owner: a `core` primitive that builds a frozen instance of a `value_class` from a table of attributes without calling `init`, next to `core.allocate`; `schema` uses it for class-bound parts whose class is a `value_class`. Tests first in `packages/core` and `packages/schema`.
3. DONE OQ-93 (2), decided by the owner: `Schema:build(content, { method, coerce = true })` converts texts with the rules of `coerce`, then builds; defaults apply once, `schema.sent` records only what was provided.
4. DONE The official JSON Schema test suite (supported subset): a pinned entry in `packages/schema/tests/external.lua` fetched by `fetch-fixtures` like the data of `json` (skipped locally without network, enforced in CI), a runner with an explicit list of the unsupported cases and the reason of each.
5. DONE Schemas from `core` enumerations (a `schema.enumeration` taking a `core.enumeration`).
6. DONE OQ-95, decided by the owner: `Schema:represent(value)` (provisional name), the conversion of an instance to plain JSON-ready values for responses: enumeration members become names, only declared attributes are kept, nested class-bound parts, arrays, maps and unions are converted, bounded by the depth guard and the work budget; nil attributes are omitted, `json.null` stays null, no defaults, no validation; a cycle ends with the depth limit error. Tests first (including `json.encode` of the result, value classes, enumerations, undeclared attributes dropped, tagged union and union), README, how-to, explanation page, CHANGELOG.
7. DONE (English and French) Docs: tested examples, an explanation page, the glossary check, the generated reference. The French pages are done (translator-fr).
8. Definition-of-done check and `/review-package` with the reviewer agents, then fix the findings.
9. Finish: delete `HANDOFF.md`, tick the roadmap item, CI green on the three platforms, mark the pull request ready and ask for the owner's review.

## Open question issues

- Every entry of `docs/open-questions.md` has a mirror issue (labels `open-question`, `oq:*`, `package:*`; see the note at the top of the file and `.github/ISSUE_TEMPLATE/open-question.md`). When this branch adds an open question (for example for the `pattern` translator), create its issue from the template, never with `needs-decision` or `blocked`. OQ-85 is #131 (closed). The template and labels reach `main` with this pull request.

- OQ-86 resolved (2026-11-07): the declaration warning falls back to `log.default()` only when `hecate.log` is already in `package.loaded` (no dependency on `log`); implement this fallback in `schema.string` when `log.default()` exists (kernel first step); until then only the `logger` option works.

## Decisions taken (and where they are recorded)

- Validation-core choices (Lua pattern, `integer` refuses 1.0, nullable is json.null only, union is anyOf, ...): OQ-85.

## Doubts and questions for the owner

- `schema.enumeration(core_enumeration)` represents a value by its name (the specification does not say; a member object is not JSON). A name is accepted, a member object never is; `build` returns the member, but `json.encode` of a member (a frozen value) writes its attributes `name`, `ordinal` and `enumeration`, not the name, so a built instance does not round-trip to the content it came from. The owner may want the member to encode as its name, or the underlying ordinal accepted. The violation code is `enum`, the one of the existing literal set (not a new `enumeration` code). The enumeration is inlined, not a definition, unless wrapped in `named`; the emission carries `type` string for a core enumeration only.
- OQ-94 implemented: the encoder follows a function `__pairs`; a `__pairs` returning no iterator function is a Lua error, a closing value is ignored, an iteration that never yields cannot be interrupted, and an iteration of more than about `max_size / 2` entries is a `size_limit` failure even when keys repeat. Conservative choices.
- Name chosen: `core.instantiate_value`, as proposed (glossary has no term for it); an extra predicate `core.is_value_class` was added so that `schema` can choose the path without a trial call.
- Otherwise none open for the owner on this item. The questions OQ-85 to OQ-92 are all resolved (rows in the Resolved table of `docs/open-questions.md`, mirror issues closed); the remaining open questions belong to other packages and must not be resolved by this run.

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
