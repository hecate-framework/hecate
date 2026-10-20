# `hecate-json`

> Fast, correct JSON codec (RFC 8259) with integer/float fidelity, explicit null and array markers, and precise error positions.

| | |
|---|---|
| Module | `hecate.json` |
| Rock | `hecate-json` |
| Layer | 1 — Runtime |
| Roadmap phase | 1 |
| Status | Lua API, pure-Lua reference backend and native yyjson decoder; Rust encoder; JSONTestSuite corpus and a differential fuzz test run on both backends |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core) |
| Used by | `cli`, `doc`, `hecate`, `http`, `kernel`, `log`, `openapi`, `schema`, `security`, `test` |
| Native code | C decoder (yyjson), Rust encoder (OQ-5, ADR 0021) |
| Specification | [schemas-and-contracts.md](../../docs/architecture/schemas-and-contracts.md) |
| Decisions | [ADR 0020](../../docs/adr/0020-json-yyjson-decoder-serde-encoder.md), [ADR 0021](../../docs/adr/0021-rust-native-modules.md) |
| Agent | [`pkg-json`](../../.claude/agents/pkg-json.md) |
| Repository | read-only mirror `hecate-framework/hecate-json`, generated from this directory (ADR 0017) |

## Responsibilities

- `encode`, `decode`, pretty printing, canonical key ordering option
- `json.null`, `json.array` markers resolving Lua table ambiguity
- integer versus float preservation (Lua 5.5 integer subtype)
- precise error positions

## Non-goals

- schema validation (see `schema`)

## Standards and references

- RFC 8259
- RFC 6901 (JSON Pointer)
- I-JSON, RFC 7493

## Public API

```lua
local json = require("hecate.json")
```

| Name | Description |
|---|---|
| `json.encode(value, options?)` | Encodes a Lua value as JSON text that is always valid UTF-8. Options: `pretty`, `indent` (spaces or a string of spaces and tabs), `canonical` (`true`: members in RFC 8785 order, UTF-16 code units; `"rfc8785"`: the full JSON Canonicalization Scheme), `max_depth` (default 1000, at most 10000), `max_size` (default 16 MiB). |
| `json.decode(text, options?)` | Decodes JSON text (RFC 8259). Options: `max_depth`, `max_size`. |
| `json.null` | The value of JSON `null` (unique, immutable, never `nil`). |
| `json.array(t?)`, `json.object(t?)` | Mark a table as a JSON array or object (a new empty table without argument); return the table. |
| `json.is_array(v)`, `json.is_object(v)` | Tell whether a value carries a marker. |
| `json.JsonError`, `json.DecodeError`, `json.EncodeError` | Errors on the `hecate.core` hierarchy, with stable codes `hecate.json.*`. |

Value model (the same for every backend, ADR 0020):

- A Lua integer is a JSON integer; a float is always written with a decimal point or an
  exponent, so `1.0` stays a float. NaN and the infinities raise `EncodeError`.
- An integer literal that does not fit in 64 bits decodes as a float. `-0` is an integer literal and
  decodes as the integer `0`; `-0.0` and `-0e0` are floats and keep their sign.
- `decode` returns every array marked with `json.array` and every object marked with
  `json.object`; an empty `[]` and an empty `{}` therefore round-trip.
- On encoding, an unmarked table is an array when all its keys are positive integers, an object
  when all keys are strings, an **object when empty**, and an error otherwise (OQ-48). A hole in an
  array (`{ 1, nil, 3 }`) is written as `null`, so `[1,null,3]`; the table must stay dense (highest
  index at most twice the number of entries plus 16). A `nil` at the end of a table cannot be seen
  by Lua: write `json.null` explicitly. The codec exposes `json.is_array` and `json.is_object` next
  to the markers.
- `canonical = true` orders object members as RFC 8785 section 3.2.3 does (UTF-16 code units).
  Numbers keep the codec's own fidelity format (integers stay integers, floats keep their point):
  the text is stable, but it is not RFC 8785 text.
- `canonical = "rfc8785"` is the full JSON Canonicalization Scheme (RFC 8785), for signing and
  hashing: compact text (it cannot be combined with `pretty` or `indent`), members in UTF-16 order,
  and every number written as an IEEE double in the ECMAScript format (`1.0` is `1`, `-0.0` is `0`,
  `1e21` is `1e+21`). An integer beyond +-2^53 raises `EncodeError` (reason `integer_out_of_range`)
  instead of being silently rounded, since two different integers would then sign alike. Strings
  need no extra step: the escaping of the codec is the one the RFC prescribes.

## Inputs `decode` rejects on purpose

RFC 8259 leaves these cases open or permits them, and parsers disagree on them. `decode` rejects
them with a `DecodeError` whose `context.reason` and message say what to fix (I-JSON, RFC 7493, is
the reference):

| `context.reason` | Input | Why it is rejected | What to do |
|---|---|---|---|
| `duplicate_key` | `{"a":1,"a":2}` | Parsers disagree on which value wins (RFC 7493 section 2.3). | Make member names unique at the source. |
| `lone_surrogate` | `"\ud800"` | A surrogate escape is valid only as half of a pair (RFC 8259 section 8.2, RFC 7493 section 2.1). | Write the character itself or its pair, e.g. `"\ud83d\ude00"`. |
| `byte_order_mark` | text starting with bytes `EF BB BF` | RFC 8259 section 8.1 lets parsers ignore it, and they differ. | Strip the first three bytes before decoding. |
| `number_out_of_range` | `1e999` | It does not fit in a 64-bit float; parsers answer infinity, error or clamp. | Send the number as a string, or a value within about 1.8e308. |
| `invalid_utf8` | a string with bytes that are not UTF-8 | The text must be UTF-8 (RFC 8259 section 8.1). | Re-encode the source as UTF-8. |
| `depth_limit`, `size_limit` | nesting beyond `max_depth`, text beyond `max_size` | Protection against hostile input. | Raise the option if the input is trusted. |

Errors: `DecodeError.context` has `reason`, `offset` (bytes before the offending byte, from 0),
`line` and `column` (from 1, in characters); `EncodeError.context` has `reason` and `path` (a JSON
Pointer, RFC 6901). Backends: the native module `hecate.json.native` is used when present,
otherwise the pure-Lua reference backend `hecate.json.internal.reference`, which is also the test
oracle; callers cannot tell them apart.

The native module (`csrc/native.c`, vendored yyjson in `csrc/vendor`) decodes with yyjson and builds
the same values as the reference backend (the `null` value and the array and object metatables of the
Lua side, kept through `bind`; integers beyond 2^63 - 1 become floats; `-0` is the integer `0`). A valid
text never leaves C. When yyjson rejects a text, or accepts one the codec rejects on purpose (a
duplicate member name, nesting beyond `max_depth`, text beyond `max_size`, a byte order mark, a
number outside the double range, a negative zero), the binding hands the same text to the reference
decoder, which names the reason, message and offset: the failures are identical by construction, and
a hostile text costs one extra reference pass. Build it with `lua tools/run.lua build-native json`
(needs a C compiler and the Lua headers; `LUA_INC` names the include directory) or with
`luarocks make`.

The encoder is a second, optional native module, `hecate.json.encoder_native` (Rust through `mlua`,
`native/`, ADR 0021; `build-native json` builds it too when `cargo` exists, the Rust toolchain is
pinned in `native/rust-toolchain.toml`). It walks the Lua value itself and writes the same text as the
reference encoder: the same escaping, member and array rules, markers, `indent`, `canonical` order
(UTF-16 code units) and float format (the fewest of 15 to 17 digits). It never reports a failure: for
a value it cannot or must not write (ambiguous table, limit reached, NaN, invalid UTF-8, unsupported
type), for `canonical = "rfc8785"` and for nesting beyond 200 levels (it recurses on the native stack)
it returns `nil` and the reference encoder answers, so reasons, messages and paths exist once. When
the module is absent the reference encoder writes everything. It is not part of the rockspec yet
(binary rocks, ADR 0021).

## Layout

```text
src/hecate/json/init.lua   public entry point
src/hecate/json/errors.lua error classes
src/hecate/json/internal/  markers, backend seam, reference backend, error positions
tests/unit/  tests/suites/ shared suites run per backend; tests/external.lua pins the corpus
examples/    tested examples of the reference pages
csrc/        C decoder (vendored yyjson in csrc/vendor)
native/      Rust encoder (Cargo workspace)
```
