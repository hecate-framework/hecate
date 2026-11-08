# Schemas and contracts

Packages: `schema`, `openapi`. Status: specification.

## `hecate.schema`

A schema is a runtime value describing a type. The same value drives coercion,
validation, JSON Schema emission, OpenAPI components, documentation and test data
generation.

### Types

| Kind | Constructors (illustrative) |
|---|---|
| Base types | `boolean`, `integer`, `number`, `string`, `null`, `any` |
| Refinement keywords | `minimum`, `maximum`, `exclusive_minimum`, `exclusive_maximum`, `multiple_of`, `min_length`, `max_length`, `pattern`, `format` (`email`, `uri`, `uuid`, `date`, `date-time`, ...), `enum`, `const` |
| Product | `object { property = schema, ... }` with `optional`, `nullable`, `default`, `additional_properties` |
| Collections | `array(item, { min_items, max_items, unique_items })`, `map(key, value)` |
| Sum | `union { a, b }`, `tagged_union("kind", { variant = schema })` |
| Literal | `literal "ok"` |
| Class-bound | `of(Class)` — the primary way to name and reuse a schema; becomes an OpenAPI component named after the class |
| Named | `named("User", schema)` — opt-in for an inline DTO without a class; becomes an OpenAPI component |
| Enumeration | `enumeration(core_enumeration)` |
| Custom | `refine(base, predicate, description)` — predicate must also be describable for docs |

`multiple_of` takes a whole-number divisor greater than zero; a fractional divisor such as `0.01` is refused at declaration (OQ-87), because binary floats cannot express decimal steps and JSON Schema has no keyword for decimal places. Use integers in minor units (cents), or a string with a `pattern` for a fixed number of decimals; a decimal type is planned (roadmap).

Lua integers and floats are distinguished (`integer` rejects `1.5`; `number` accepts both).

Names: class-bound schemas own the schema names. A schema without a class and without `named` is inlined.
Two different bodies under one name in one emission raise `ArgumentError`, whose message names the colliding
name and says whether each comes from a class or from `named`; equal bodies share one definition.

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
- `default(schema, value)`: `coerce` (texts) and `build` (JSON content, except PATCH) give an absent property a fresh copy of the value; an explicit `null` and a PATCH never take it, `validate` never supplies it, and `sent` stays false for a defaulted attribute (OQ-88).
- `build(content, { method, coerce })`: a class-bound part whose class is a `value_class` is built with `core.instantiate_value` from its validated attributes, children first (no `init` call). With `coerce = true` the texts of a request (path, query, headers) are converted with the rules of `coerce` and then built in one call: defaults apply once, in the conversion and never for a PATCH, `sent` records only the attributes provided, and a failed conversion returns the `coercion` violations of `coerce` (OQ-93).
- Unknown properties (`additional_properties`): rejected by default for request content (configurable per schema).
- Members of an `object` schema are *properties* (the JSON Schema term); *fields* are HTTP header fields only.

### Classes and schemas

Entities and value objects may expose a schema (`User.representation`). Conversion
between instances and representations is explicit and declared once (which attributes
are exposed, renamed or computed).

### Emission

`schema:to_json_schema()` produces JSON Schema 2020-12. Every construct must have an
exact emission; constructs that cannot be expressed in JSON Schema are not allowed.

### The `pattern` option

`pattern` is a **Lua pattern**, not a regular expression (OQ-85, point 1). Validation in Lua uses it as written.
Emission translates it to an ECMA-262 regular expression (JSON Schema 2020-12 section 6.3.3) with
`hecate.schema.pattern`, a translator written in Lua. The translation is exact for the subset below and
**refuses** everything else with an `ArgumentError`; it never approximates.

| Lua pattern | ECMA-262 |
|---|---|
| a literal ASCII character | the character, escaped when it is special (`^ $ \ . * + ? ( ) [ ] { } \| /`) |
| `.` | `[\s\S]` |
| `%a %c %d %g %l %p %s %u %w %x` | the ASCII range set (`%a` is `[A-Za-z]`, `%d` is `[0-9]`, `%s` is `[ \t\n\x0B\f\r]`, ...) |
| `%A %C %D %G %L %P %S %U %W %X` | the negated range set |
| `%` followed by a non-alphanumeric character | that character, as a literal |
| `[set]`, `[^set]` | a class of ASCII ranges; ranges `a-z`; classes `%a`... inside; complemented classes (`%S`) inside a set are refused |
| `*`, `+`, `?` after a single-character item | the same quantifier |
| `-` after a single-character item | `*?` (lazy) |
| `^` at the start, `$` at the end | `^`, `$` |
| `^` or `$` elsewhere, a quantifier character where an item is expected, `-` where an item is expected | a literal, escaped |
| `( ... )` | a capturing group `( ... )`; a quantifier after `)` is a literal, as in Lua |
| `%1` to `%9` | `(?:\1)` |

Refused: `%b`, `%f`, the position capture `()`, any non-ASCII byte, a malformed pattern (unbalanced capture,
unfinished set or escape), `%` followed by another alphanumeric character. Characters ordinary in Lua but special in a
regular expression (braces, vertical bar, slash) are escaped.

Declaring a `string` with a `logger` option (an object with `warning(message, fields)`) reports a pattern that cannot be
translated at declaration; emission refuses it.

Lua matches **bytes**, ECMA-262 matches UTF-16 code units, so `.`, negated sets and negated
classes differ from the emitted expression on non-ASCII input (for example `^.$` rejects `"é"` in Lua and accepts it in
ECMA-262). The emitted expression is exact for ASCII input (the ASCII-pinned classes of OQ-85, point 1).

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

## JSON codec (`json`)

Every schema, contract and test datum that crosses the wire goes through `hecate.json` (RFC 8259, I-JSON RFC 7493), whose
behaviour is specified here and in `packages/json/README.md`:

- **Value model.** Lua integers and floats stay distinct (a float is always written with a point or an exponent),
  `json.null` is a unique value, `json.array` and `json.object` mark tables so that `[]` and `{}` round-trip, and an
  unmarked empty table is an object. `decode` rejects what parsers disagree on (duplicate member names, lone
  surrogates, a byte order mark, numbers outside the double range) with a `DecodeError` that has a `reason`, an `offset`,
  a `line` and a `column` (a duplicate member name has the reason only); `encode` rejects what has no JSON representation with an `EncodeError` that has a `reason`
  and the JSON Pointer (RFC 6901) `path` of the offending value.
- **Two native modules, no fallback.** The decoder (C over yyjson) and the encoder (Rust, `serde_json` through `mlua`)
  are required at run time on every platform; each produces its own failures in the vocabulary above, and a module that
  is not built raises an error naming `lua tools/run.lua build-native json` (OQ-53, ADR 0020 and ADR 0021). The seam is
  `hecate.json.internal.backend`; packages that depend on `json` need the modules in their tests and in CI.
- **Canonical output.** `canonical = true` orders members by UTF-16 code units (RFC 8785 section 3.2.3);
  `canonical = "rfc8785"` is the full JSON Canonicalization Scheme, for signatures and hashes.
- **Tested by fixtures, not by an oracle.** Expected outputs (`packages/json/tests/fixtures`), property tests
  (`decode(encode(x)) == x`, never invalid UTF-8, no crash), RFC 8785 appendix B vectors and the JSONTestSuite corpus.
