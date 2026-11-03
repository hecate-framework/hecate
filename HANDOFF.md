<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `schema`: refinement types, composition, coercion, validation with JSON Pointer error paths, JSON Schema 2020-12 emission.
- status: in-progress            <!-- in-progress | waiting-ci | waiting-owner -->
- lock_until: 2026-11-03T20:30:00Z
- last_update: 2026-11-03T15:50:00Z

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

## Next steps

1. (2b) Remaining emission work: official JSON Schema test suite (supported subset), the `1.0` gap is confirmed; (pattern translator done); more formats (uri), core enumeration support, recursive schemas (named done).
2. Class-bound schemas (OQ-50, resolved 2026-11-03, see the Resolved row for the full decision): an interface requiring a class-level `schema()`, `schema.of(Class)` (and of a module name string), lazy memoized resolution with cycle closing through `$defs`/`$ref` (this also delivers recursive schemas), the presence set `schema.sent(instance, name)`, instance construction convention (to settle conservatively and record in a new OQ), HTTP-method relaxation (PATCH) derived by the validator. Tests: self reference, mutual pair, cycle of three classes (validation, coercion, emission); check the json decoder depth limit.
3. Docs: website pages, tested examples, glossary check, reference generation (`DEFAULT_PACKAGES`).
4. Benchmarks (`benchmarks/`) for compiled validators.

## Open question issues

- Every entry of `docs/open-questions.md` has a mirror issue (labels `open-question`, `oq:*`, `package:*`; see the note at the top of the file and `.github/ISSUE_TEMPLATE/open-question.md`). When this branch adds an open question (for example for the `pattern` translator), create its issue from the template, never with `needs-decision` or `blocked`. OQ-85 is #131 (closed). The template and labels reach `main` with this pull request.

## Decisions taken (and where they are recorded)

- Validation-core choices (Lua pattern, `integer` refuses 1.0, nullable is json.null only, union is anyOf, ...): OQ-85.

## Doubts and questions for the owner

- OQ-85 is resolved (moved to "Resolved" in `docs/open-questions.md`): the owner confirmed every point. Remaining work for it: write the specification section of the `pattern` subset, then build the translator and remove the stop-gap refusal in `to_json_schema` (and its test `test_pattern_is_refused`, replaced by translation tests).

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
