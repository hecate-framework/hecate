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
| Collections | `array(item, { min_items, max_items, delimiter, unique_items })`, `map(value, { min_properties, max_properties })` (string keys only, no key schema, OQ-87) |
| Sum | `union { a, b }`, `tagged_union("kind", { variant = schema })` |
| Literal | `literal "ok"` |
| Class-bound | `of(Class)` — the primary way to name and reuse a schema; becomes an OpenAPI component named after the class. The interface `Representable` requires the class-level `schema()`, and `of` refuses a class that does not declare it |
| Named | `named("User", schema)` — opt-in for an inline schema without a class; becomes an OpenAPI component |
| Enumeration | `enumeration(core_enumeration)`, `enumeration({ "a", "b" })` |
| Custom | `refine(base, predicate, description)` is not offered: a predicate cannot be emitted as JSON Schema, so the emitted contract would be looser than the validator (OQ-97, until a consumer needs it) |

`enumeration(core_enumeration)` accepts the names of the enumeration, in declaration order: a member object is not a JSON
value, whereas its name survives `json.encode` and `json.decode` unchanged. Coercion of a text reads the name, a violation has
the code `enum` with the names in `context.values`, the emission is `type` string with `enum`, and `build` turns a name into the
member. A default is given as a name. The names are read once, at declaration. The schema is inlined unless wrapped in `named`.

`multiple_of` takes a whole-number divisor greater than zero; a fractional divisor such as `0.01` is refused at declaration (OQ-87), because binary floats cannot express decimal steps and JSON Schema has no keyword for decimal places. Use integers in minor units (cents), or a string with a `pattern` for a fixed number of decimals; a decimal type is planned (roadmap).

A union must not contain null (OQ-99): `nullable` is the only way for a property to accept null. `union(alternatives)` therefore
refuses at declaration, with `ArgumentError`, every alternative that accepts null (OQ-100): `null()`, a `nullable` schema, `literal(json.null)` and an `enumeration` whose
constants contain `json.null`, directly or under `named`, `optional` or `default`, and the message names the kind and tells to write `nullable(union(...))`. This is a declaration error, not a violation
code: no value is involved. A literal null or such an enumeration stays allowed as a plain property. `any()` is not refused, it accepts every value, null included, by an explicit choice; the variants of a
`tagged_union` are objects and are unaffected.

Lua integers and floats are distinguished (`integer` rejects `1.5` and `1.0`; `number` accepts both).

Parameter names follow the role: `item` is the element schema of an `array`, `value` the value schema of a `map`, `inner` the
schema wrapped by `optional`, `nullable`, `default` and `named`, and `alternatives` the list of a `union`. Each constructor has one
option class (`StringOptions`, `IntegerOptions`, `NumberOptions`, `ArrayOptions`, `MapOptions`, `ObjectOptions`), and a `string` takes
`min_length`, `max_length`, `pattern`, `format` and an optional `logger`.

`Representable` is the interface of a class whose instances have a representation (RFC 9110 section 3.2), declared once by the
class-level function `schema()` that `of` calls. A class that declares it (`implements = { schema.Representable }`) and has no
`schema` raises `ConformanceError` at finalisation. `of` refuses a class that does not declare the interface, even when it has a
`schema` function: the declaration is the contract. The check runs at declaration when the class is already finalised, otherwise at
the first use, and also applies to the module name form (after the module is loaded). The refusal is an `ArgumentError` that names
the class and the interface and says how to fix it.

#### Return conventions

`validate` returns `true`, or `false` and the list of violations. `coerce` and `build` return two values: `true` and the converted or
built value, or `false` and the list of violations; they never raise for content that does not conform. `check` is the raising form
of `validate` only: it returns the value or raises `ValidationError` with `context.violations`. `represent` returns the plain
value and raises `ValidationError` when it cannot represent it. A declaration that is wrong raises `ArgumentError`.

Names: class-bound schemas own the schema names. A schema without a class and without `named` is inlined.
Two different bodies under one name in one emission raise `ArgumentError`, whose message names the colliding
name and says whether each comes from a class or from `named`; equal bodies share one definition.

### Violation codes

Every violation has a `path` (a JSON Pointer), a `code`, a `message` and a `context`. The codes are **stable**: a code is never
renamed or removed without a major version, and a client may switch on it. The `message` is for people and may be reworded; it
never contains a value sent by the client. There are two namespaces: the short violation codes below (`minimum`, `required`), and the
dotted codes of errors such as `hecate.core.ValidationError`, which wraps the violations in `context.violations`.

| Code | Context fields | Emitted by |
|---|---|---|
| `type` | `expected`, `received` | every kind, when the value has another type (`integer` also refuses a whole float) |
| `required` | `property` | `object`, and `tagged_union` for a missing tag |
| `additional_properties` | `property` | `object`, for an undeclared property |
| `minimum`, `maximum` | `minimum`, `maximum` | `integer`, `number` |
| `exclusive_minimum`, `exclusive_maximum` | `exclusive_minimum`, `exclusive_maximum` | `integer`, `number` |
| `multiple_of` | `multiple_of` | `integer`, `number` |
| `min_length`, `max_length` | `min_length`, `max_length` | `string` |
| `invalid_utf8` | none | `string`, when a length is declared and the text is not UTF-8 |
| `pattern` | `pattern`, and `reason`, `max_bytes` | `string` |
| `format` | `format`, and `reason`, `max_bytes` | `string` |
| `literal` | `value` | `literal` |
| `enum` | `values` | `enumeration` |
| `min_items`, `max_items` | `min_items`, `max_items` | `array` |
| `unique_items` | `index` | `array` |
| `min_properties`, `max_properties` | `min_properties`, `max_properties` | `map` |
| `union` | `alternatives` | `union` |
| `tagged_union` | `tag`, `values` | `tagged_union`, for an unknown tag |
| `coercion` | `expected` | `coerce`, and `build` with `coerce = true`, for a text that cannot be converted |
| `depth_limit` | `max_depth` | every container, beyond 1000 levels |
| `complexity_limit` | `max_steps` | any call that spends more than 1,000,000 steps |
| `too_many_violations` | `max` | the call, once 100 violations are kept; it replaces the 101st |

`context.reason` of `pattern` and `format` is `too_long_for_pattern` (the string is longer than 65536 bytes and no `max_length` is
declared; `context.max_bytes` is the ceiling) or, for `pattern` only, `malformed_pattern` (Lua gave up on the match: "pattern too
complex"). The codes are the type `hecate.schema.ViolationCode` in the annotations; `Violation.code` has that type.

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
- Unknown properties (`additional_properties` option): rejected by default (violation `additional_properties`), configurable per schema.
- Bounded output: a call keeps at most 100 violations; the 101st is replaced by one `too_many_violations` violation (`context.max = 100`), validators stop descending, and a property name echoed in a violation (path and `context.property`) is cut to 64 bytes. `unique_items` hashes scalars and compares tables by signature bucket, and spends the work budget per item and per comparison.
- Members of an `object` schema are *properties* (the JSON Schema term); *fields* are HTTP header fields only.

### Classes and schemas

Entities and value objects may expose a schema (`User.representation`). Conversion
between instances and representations is explicit and declared once (which attributes
are exposed, renamed or computed).

A response goes through the same schema: `schema:represent(value)` converts an instance, or any value built
by hand, into the plain values of its representation (OQ-95), which the kernel then encodes with `json.encode`
(`json` stays unaware of classes). Only the attributes the schema declares are kept, so an undeclared attribute
never leaks; enumeration members become their names; nested class-bound parts, arrays, maps, unions and tagged
unions convert recursively, in fresh tables. An absent attribute is omitted, `json.null` stays null, defaults are
not applied and the value is not validated (a response that does not conform is a bug of the server), except to
choose the alternative of a union. The depth guard and the work budget of validation apply; a cycle in the object
graph ends with a `depth_limit` error. Only the fields of the instance itself are read, never a method or a prototype field of its class (`schema.of` refuses a declared property named like a class member), and a function value is skipped. A nullable attribute that is nil on an instance made by `build` and was sent as `null` is represented as `null`, so that the content round-trips; an instance that was not built omits its nil attributes.

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

A malformed pattern (the faults Lua reports only when a match reaches them: a trailing `%`, an unclosed set or capture, an invalid capture index, `%f` without a set, `%b` without two characters) is refused at declaration with `ArgumentError`, and a match that still fails at validation time ("pattern too complex") is a `pattern` violation with `context.reason = "malformed_pattern"`. Pattern matching can backtrack, so patterns should be anchored. `pattern` and `format` are skipped for a value with an `invalid_utf8` or `max_length` violation, and, without `max_length`, a string longer than 65536 bytes is not matched: it gets a `pattern` (or `format`) violation with `context.reason = "too_long_for_pattern"`.

Declaring a `string` with a `logger` option (an object with `warning(message, fields)`) reports a pattern that cannot be
translated at declaration, as `schema: pattern "%bxy" cannot be emitted: %b has no exact translation` (the pattern and the reason
are also in `fields`); emission refuses it with an `ArgumentError` whose message says that Lua validation is unaffected and how to
rewrite the pattern: with sets, classes, `format`, `min_length` or `enum`.

Lua matches **bytes**, ECMA-262 matches UTF-16 code units, so `.`, negated sets and negated
classes differ from the emitted expression on non-ASCII input (for example `^.$` rejects `"é"` in Lua and accepts it in
ECMA-262). The emitted expression is exact for ASCII input (the ASCII-pinned classes of OQ-85, point 1).

### JSON Schema outside the emitted subset

The emission covers `type`, `enum`, `const`, the numeric, string, array and object refinements, `properties`, `required`,
`additionalProperties`, `items`, `anyOf`, `oneOf`, `default`, `format`, `$defs` and local `$ref`. These keywords are **deliberately
not emitted**, and are out of scope until a consumer needs them: `allOf`, `not`, `if`, `then` and `else`, `contains`, `prefixItems`,
`patternProperties`, `propertyNames`, `dependentSchemas`, `dependentRequired`, `unevaluatedProperties`, `unevaluatedItems`, `$id`,
anchors, `$dynamicRef`, remote `$ref` and the `content` keywords. `oneOf` is emitted only by `tagged_union`; a `union` is `anyOf`.

### Generation (not yet implemented, planned)

`schema:generate(seed)` would produce valid sample values (for documentation examples and
property-based tests); `schema:generate_invalid(seed)` would produce values violating exactly
one constraint, with the expected violation. Neither exists yet; the `test` package carries them. The same holds for the
generation of `---@meta` files for LuaLS, carried by `doc` or `cli`.

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
