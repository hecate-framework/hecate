# Schemas and contracts

Packages: `schema`, `openapi`. Status: specification.

## `hecate.schema`

A schema is a runtime value describing a type. The same value drives coercion,
validation, JSON Schema emission, OpenAPI components, documentation and test data
generation.

### Types

| Kind | Constructors (illustrative) |
|---|---|
| Base | `boolean`, `integer`, `number`, `string`, `null`, `any` |
| Refinement keywords | `minimum`, `maximum`, `exclusive_minimum`, `exclusive_maximum`, `multiple_of`, `min_length`, `max_length`, `pattern`, `format` (`email`, `uri`, `uuid`, `date`, `date-time`, ...), `enum`, `const` |
| Product | `object { field = schema, ... }` with `optional`, `nullable`, `default`, `additional` |
| Collections | `array(item, { min_items, max_items, unique_items })`, `map(key, value)` |
| Sum | `union { a, b }`, `tagged_union("kind", { variant = schema })` |
| Literal | `literal "ok"` |
| Named | `named("User", schema)` — becomes an OpenAPI component |
| Enumeration | `enumeration(core_enumeration)` |
| Custom | `refine(base, predicate, description)` — predicate must also be describable for docs |

Lua integers and floats are distinguished (`integer` rejects `1.5`; `number` accepts both).

### Coercion

Inputs from paths, query strings and header fields are strings. Each base type defines
a coercion from text (`"42"` → `42`, `"true"` → `true`, comma or repeated-key arrays per
OpenAPI `style`/`explode`). JSON content is decoded first, then validated without
coercion (except where explicitly allowed).

### Validation

- Validation collects **all** violations, each with a JSON Pointer path (RFC 6901), a
  machine-readable code and a human message.
- Schemas compile to validator closures at boot; validation must not walk the schema
  description at request time.
- Unknown properties: rejected by default for request content (configurable per schema).

### Classes and schemas

Entities and value objects may expose a schema (`User.representation`). Conversion
between instances and representations is explicit and declared once (which attributes
are exposed, renamed or computed).

### Emission

`schema:to_json_schema()` produces JSON Schema 2020-12. Every construct must have an
exact emission; constructs that cannot be expressed in JSON Schema are not allowed.

### Generation

`schema:generate(seed)` produces valid sample values (for documentation examples and
property-based tests); `schema:generate_invalid(seed)` produces values violating exactly
one constraint, with the expected violation.

## `hecate.openapi`

- Assembles an OpenAPI **3.1** document from: the route table, route metadata, named
  schemas (components), security declarations, and project configuration (`title`,
  `version`, `servers`, `contact`, `license`, external docs).
- The project version in the manifest becomes `info.version` by default.
- Problem details schemas (RFC 9457) are included and referenced by error responses.
- Output: JSON (default) and YAML. Deterministic ordering, so that diffs are stable.
- Served at `/openapi.json` when enabled (default on in development), with an optional
  interactive reference page (embedded static assets; no CDN dependency).
- `hecate contract export` writes it; `hecate contract diff <ref>` compares two
  contracts and classifies changes as breaking or non-breaking (removed route, narrowed
  input type, removed response field, new required parameter, ...). CI can fail on
  unannounced breaking changes.

## Single source of truth

Nothing about the HTTP interface is declared twice. Documentation comments
(`summary`, `description`) live in the route declaration; LuaLS annotations document
code, not the HTTP contract. The documentation generator merges both views.
