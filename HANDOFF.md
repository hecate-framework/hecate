<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `schema`: refinement types, composition, coercion, validation with JSON Pointer error paths, JSON Schema 2020-12 emission.
- status: in-progress            <!-- in-progress | waiting-ci | waiting-owner -->
- lock_until: 2026-11-08T13:41:55Z
- last_update: 2026-11-08T09:41:55Z

## Done

- Test robustness (owner-authorised, cross-package): the public-server TLS test in `packages/net/tests/integration/tls_test.lua` is bounded and skips on infrastructure failures (loopback-tested); `fetch-fixtures` retries git fetches (`tools/lib/retry.lua`).

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

- Fix pass A of the review (S1 to S4, s1 to s4, null round trip, memoised second union pass of `represent`): commit 5cf3b69, tests `hardening_test.lua` and `represent_test.lua`; internal bounds `limits.max_violations` (100) and `limits.max_pattern_bytes` (65536); `copy_default` replaces `options.value` (no longer exposed); `schema.of` refuses a property named like a class member; `pattern.check` is the structural check of a Lua pattern. Owner decision 2026-11-08: `represent` emits `null` for a nullable attribute that was sent as `null` on a built instance.

- Step OQ-95 (owner-driven session): `Schema:represent(value)` in `schema.lua` (compiled `representer` closure per schema, made at declaration like the validators, wrapped by the shared depth guard and work budget; `reset_work` on entry), tests `represent_test.lua`, example `hecate.schema.Schema.represent`, README, architecture, how-to, explanation page, CHANGELOG. Errors are `ValidationError` with one violation in `context.violations`, as `check` does.

- French mirror of the schema pages (translator-fr): `website/fr/how-to/validate-with-schemas.md` and `website/fr/explanation/schemas-and-contracts.md` (examples copied verbatim under the same markers), links added to the French how-to, explanation and reference indexes, terms in `website/fr/glossary-terms.md` only. `source_revision` is the full hash of the last commit of the English page (135eb4535b8734db2bc5ef6c3f7faf77ac8299ea for both pages; the indexes carry the last commit of their English index), as the router item did. No CHANGELOG line (the router item had none for its French page). check-glossary, check-links, check-docs-examples, check-changelog, lint, typecheck pass.

- Fix pass B of the review (API, documentation, terminology; owner-driven session): commits 3130f07 (code, tests `review_b_test.lua`), 116ae90 (specification, README, how-to, explanation, glossary) and fdae972 (French pages, CHANGELOG). Violation code `additional_property` is now `additional_properties`, with the "Violation codes" table and `hecate.schema.ViolationCode`; `schema.HasSchema`; `Schema:members()` method; option classes; internals `---@field package`; return overloads; messages (accepted options and formats, received type, pattern refusal, logger text, `default`); how-to reordered with the tested `Schema.check` example; keyword limits and "planned, not implemented" notes; glossary rows; `Record` renamed `Options`; the two French pages refreshed (`source_revision` 116ae90).

- Fix pass C of the review (tests; owner-driven session): commits d460c46, 5e3e8f2, 9801f4d, 89b076e, 386e5d3, ec05efc. Seeded differential of `validate` against the emitted schema (`differential_test.lua`, 3200 pairs, `tests/support/prng.lua`, `HECATE_TEST_SEED`), the pin that `format` is only an annotation when emitted, the round trip `roundtrip_test.lua` (POST and PATCH), the suite runner with position-aware gaps and pinned counts (`HECATE_TEST_VERBOSE` prints them), step counts in place of every `os.clock` bound (private `schema._steps()`), hostile chains of 20000 nodes, `options_test.lua`, `violation_codes_test.lua` (parses the specification table), `robustness_test.lua`, and limits restored through `tests/support/protected.lua`. Details and the findings of the new tests are in the review, "Fix pass C".

- Fix pass D of the review (performance; owner-driven session): commits 7ba31a5 (benchmark scenarios, P4), 5fc6d89 (P2, memoisation only inside alternative attempts, lazy stores), 8dca32e (P1, path stack `segments` and `path_to`, `paths_test.lua`), 00289db (map coercion violations in key order, tests). P3 (cached `max_steps`, inline step test, guard folded into the object validator) was measured and reverted: no scenario gained 10 percent. Undeclared properties were already sorted; the map coercion order was the nondeterminism. P5 and P6 are on the roadmap Benchmarks item. Details, reasons and the failing-input cost are in the review, "Fix pass D". Medians of 5 runs of `bench schema/validate --yes` on a shared VM (host not quiet, indicative only), operations per second, baseline then final with max/min in brackets:

| Scenario | Baseline | Final | Change |
|---|---|---|---|
| validate record | 287k (1.15) | 311k (1.06) | +8% |
| validate array of 100 | 2.75k (1.02) | 3.37k (1.05) | +22% |
| validate union | 403k (1.06) | 574k (1.11) | +42% |
| coerce record | 149k (1.06) | 162k (1.10) | +9% |
| coerce array of 100 | 1.24k (1.03) | 1.69k (1.04) | +36% |
| coerce union | 182k (1.15) | 248k (1.60) | +36% |
| build record | 166k (1.07) | 181k (1.12) | +9% |
| represent record | 344k (1.09) | 388k (1.37) | +13% |
| represent array of 100 | 2.46k (1.05) | 3.79k (1.05) | +54% |
| build class-bound | 320k (1.08) | 339k (1.06) | +6% |
| build class-bound nested | 178k (1.14) | 189k (1.06) | +6% |
| validate tagged union | 866k (1.22) | 868k (1.06) | 0% |
| build tagged union | 484k (1.09) | 479k (1.15) | -1% |
| represent tagged union | 872k (1.12) | 902k (1.12) | +3% |
| validate twins 30 invalid | 7.16k (1.03) | 7.27k (1.03) | +1% |
| validate twins 30 valid | 37k (1.07) | 40k (1.08) | +10% |
| validate failing record | 33k (1.03) | 30k (1.08) | -8% |
| validate failing union | 57k (1.04) | 56k (1.12) | -1% |
| validate string with a format | 631k (1.11) | 680k (1.07) | +8% |
| validate string with a length | 3.44M (1.16) | 3.86M (1.06) | +12% |
| build with coerce, query | 120k (1.08) | 139k (1.06) | +16% |

## Doubts (OQ-95, conservative choices taken)

- The name `represent` is kept: the glossary defines the term representation (Fielding, RFC 9110), and the specification speaks of representations.
- A value of the wrong shape (not a table for an object, array or map), an unknown tag, a non-member for an enumeration and an unmatched union raise `ValidationError` (codes `type`, `tagged_union`, `enum`, `union`) instead of producing garbage.
- Map keys that are not strings are copied as they are (the encoder then refuses them); `any` deep-copies and keeps the markers, and stops at the depth guard.

## Doubts (fix pass B)

- The interface is named `HasSchema` (the provisional name): the glossary has no term for it, and the other interfaces of the repository (`FileSystem`, `Stream`) are nouns, so a rename such as `Schematic` remains possible. `schema.of` keeps requiring the function and accepts classes that do not declare the interface.
- The coercion message already read "the text is not an integer"; only a test pins it now. `context.expected` of a `coercion` violation keeps the phrase ("an integer"), unlike a `type` violation ("integer").
- `x2`: the `Class.representation` and implicit represent text of `docs/developer-experience.md` is left to the routes item. The public glossary pages (`website/*/reference/glossary.md`) are not updated, as before.

## Doubts (French mirror)

- French renderings chosen conservatively, listed in `website/fr/glossary-terms.md`: violation, schéma lié à une classe, ensemble de présence, budget de travail, unités mineures, « à échec rapide », objet de transfert de données. The public French glossary page is not updated (the English one is not either).
- The French indexes carry the English index revision although they do not list the untranslated HTTP pages.

## Owner-driven session

The owner asked on 2026-11-08 to finish this pull request the same day; an interactive session holds the lock until `lock_until` and drives the remaining steps, then releases it. A relay run must skip this pull request while the lock is in the future.

## Next steps

Only open work is listed here; finished steps move to Done (never keep a DONE line in this list). Findings, ids and statuses are in `docs/reviews/schema-review-package.md`; fix test first and record the commit of each fix there.

1. Finish: delete `HANDOFF.md`, tick the roadmap item, CI green on the three platforms, mark the pull request ready and ask for the owner's review.

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
