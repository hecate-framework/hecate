<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `schema`: refinement types, composition, coercion, validation with JSON Pointer error paths, JSON Schema 2020-12 emission.
- status: in-progress            <!-- in-progress | waiting-ci | waiting-owner -->
- lock_until: 2026-11-02T15:35:00Z
- last_update: 2026-11-02T14:05:00Z

## Done

- Step 1 (type model and validation core): `packages/schema/src/hecate/schema/{init,schema,violation}.lua`, tests in `packages/schema/tests/unit/validate_test.lua`. Types: string, integer, number, boolean, literal, enumeration, object, array, optional, nullable, union; `validate` collects all violations with JSON Pointer paths, `check` raises `ValidationError`. Schemas are value classes (immutable), validators compiled at declaration. README status, CHANGELOG, OQ-85 updated. typecheck, lint, test schema, check-boundaries pass.

## Next steps

1. Coercion of textual inputs (path, query, fields; OpenAPI style/explode).
2. JSON Schema 2020-12 emission (`to_json_schema`), differential tests against Lua validation, resolve the OQ-85 points first (pattern, `1.0` as integer); add map, tagged_union, named, format, exclusive bounds, multiple_of, unique_items, default, core enumeration support, recursive schemas.
3. Class-bound instances and the presence set `schema.sent(instance, name)` (OQ-50), HTTP-method relaxation (PATCH).
4. Docs: website pages, tested examples, glossary check, reference generation (`DEFAULT_PACKAGES`).
5. Benchmarks (`benchmarks/`) for compiled validators.

## Decisions taken (and where they are recorded)

- Validation-core choices (Lua pattern, `integer` refuses 1.0, nullable is json.null only, union is anyOf, ...): OQ-85.

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
