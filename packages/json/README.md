# `hecate-json`

> Fast, correct JSON codec (RFC 8259) with integer/float fidelity, explicit null and array markers, and precise error positions.

| | |
|---|---|
| Module | `hecate.json` |
| Rock | `hecate-json` |
| Layer | 1 — Runtime |
| Roadmap phase | 1 |
| Status | alpha — Lua API on two native modules, both required at run time (yyjson decoder in C, serde_json encoder in Rust; no pure-Lua fallback, OQ-53); expected-output fixtures, JSONTestSuite corpus and property-based fuzz tests, libFuzzer C targets (`csrc/fuzz`, `lua tools/run.lua fuzz decode`) |
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
| `json.encode(value, options?)` | Encodes a Lua value as JSON text that is always valid UTF-8. Options: `pretty`, `indent` (spaces or a string of spaces and tabs), `canonical` (`true`: members in RFC 8785 order, UTF-16 code units; `"rfc8785"`: the full JSON Canonicalization Scheme), `max_depth` (default 1000, at most 1000, the same as `decode`), `max_size` (default 16 MiB). |
| `json.decode(text, options?)` | Decodes JSON text (RFC 8259). Options: `max_depth` (default 1000, at most 1000), `max_size` (default 16 MiB): the same two limits, with the same defaults and bounds, as `encode`; a text nested deeper is a `depth_limit` error. |
| `json.null` | The value of JSON `null` (unique, immutable, never `nil`). |
| `json.array(t?)`, `json.object(t?)` | Mark a table as a JSON array or object (a new empty table without argument); return the table. |
| `json.is_array(v)`, `json.is_object(v)` | Tell whether a value carries a marker. |
| `json.JsonError`, `json.DecodeError`, `json.EncodeError` | Errors on the `hecate.core` hierarchy, with stable codes `hecate.json.*`. |

Value model (ADR 0020):

- A Lua integer is a JSON integer; a float is always written with a decimal point or an
  exponent, so `1.0` stays a float. NaN and the infinities raise `EncodeError`.
- An integer literal that does not fit in 64 bits decodes as a float. `-0` is an integer literal and
  decodes as the integer `0`; `-0.0` and `-0e0` are floats and keep their sign. The binding does not handle
  `-0` itself: this is what yyjson reads, and a test fails if a yyjson update changes it (OQ-53).
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
| `duplicate_member_name` | `{"a":1,"a":2}` | Parsers disagree on which value wins (RFC 7493 section 2.3). The native decoder gives no position for it. | Make member names unique at the source. |
| `lone_surrogate` | `"\ud800"` | A surrogate escape is valid only as half of a pair (RFC 8259 section 8.2, RFC 7493 section 2.1). | Write the character itself or its pair, e.g. `"\ud83d\ude00"`. |
| `byte_order_mark` | text starting with bytes `EF BB BF` | RFC 8259 section 8.1 lets parsers ignore it, and they differ. | Strip the first three bytes before decoding. |
| `number_out_of_range` | `1e999` | It does not fit in a 64-bit float; parsers answer infinity, error or clamp. | Send the number as a string, or a value within about 1.8e308. |
| `invalid_utf8` | a string with bytes that are not UTF-8 | The text must be UTF-8 (RFC 8259 section 8.1). | Re-encode the source as UTF-8. |
| `depth_limit`, `size_limit` | nesting beyond `max_depth`, text beyond `max_size` | Protection against hostile input. | Raise the option if the input is trusted. |

The error message echoes at most 40 bytes of the input (a member name or a number literal), cut on a character boundary, with control characters, quotes and backslashes escaped. Errors: `DecodeError.context` has `reason`, `offset` (bytes before the offending byte, from 0),
`line` and `column` (from 1, in characters); `EncodeError.context` has `reason` and `path` (a JSON
Pointer, RFC 6901).

## Native modules

The codec has no pure-Lua backend (OQ-53, owner decision of 2026-10-25: code that has no use is thrown away; the
git history keeps the one that existed). It runs on two native modules, both **required at run time** on every
platform; a module that is not built raises a `JsonError` that names the command
`lua tools/run.lua build-native json` (needs a C compiler with the Lua headers, `LUA_INC` names the include
directory, and a Rust toolchain, pinned in `native/rust-toolchain.toml`), and a module that is present but fails to
load raises its own error. `luarocks make` builds the decoder; the binary rocks of both modules come with the
release automation (ADR 0021). The modules are looked up on first use, never when `hecate.json` is required, and the
seam between them and the public module is `hecate.json.internal.backend`.

**Decoder**, `hecate.json.native` (`csrc/native.c`, vendored yyjson in `csrc/vendor`): builds the value model (the
`null` value and the array and object metatables of the Lua side, kept through `bind`; integers beyond 2^63 - 1 become
floats). A text that is too long, starts with a byte order mark or nests deeper than `max_depth` is refused before
yyjson runs (nesting is counted in one pass, without allocation). A text that yyjson rejects is reported from the
error of yyjson (a code, a message and a byte position) in the vocabulary of the codec, without a second parse: a
hostile text costs no more than a valid one. No case is handed to any other code.

Limits of the decoder, which come from its parser (yyjson) and not from the codec (OQ-54):

- The message says what yyjson found (`unexpected character '1'`), not what was expected (`expected ':'`).
- A **duplicate member name** is found after the parse, and yyjson keeps no position for it: the error has a
  `reason` and a message but no `offset`, `line` or `column`. A text that has a duplicate and another defect
  is reported with the other defect.
- A text with **several defects**, or a string with several, may be reported at another defect than the first one,
  with another `reason` among the string defects (`invalid_escape`, `lone_surrogate`, `invalid_utf8`,
  `control_character`, an unterminated string) or another `offset`.
- `-0` is whatever yyjson reads (today the integer `0`, see above): the binding does not special-case it, and will
  keep following yyjson until it can tell the two spellings apart or users ask for more (owner decision, OQ-53).
- Known issue: a number literal that is an exact tie between two doubles and is followed by a tail of more than
  about 700 zeros (for example `1.00000000000000011102230246251565404236316680908203125` and 715 zeros) is
  rounded up by yyjson, one unit in the last place from the correctly rounded value. Such a literal does not
  occur in practice.

**Encoder**, `hecate.json.encoder_native` (Rust through `mlua` and `serde_json`, `native/`, ADR 0020 and ADR 0021): walks
the Lua value itself and `serde_json` writes the text (escaping, integers, punctuation, indentation). It owns the whole
encoding contract: markers, the rules for arrays, objects and holes, `canonical` order (UTF-16 code units), the float
format (the fewest of 15 to 17 digits, or the ECMAScript format of RFC 8785 for `canonical = "rfc8785"`, integers
beyond +-2^53 refused) and the **failures**: it returns `nil` and a table `{ reason, message, path }` (the reason
and message of `EncodeFailureReason`, the JSON Pointer of the offending value), found where the walk meets the
problem, with the path built on the way out so that a successful encoding records nothing. The message of NaN says
`nan` whatever its sign (the sign of `0/0` differs between processors). The work of the encoder is bounded by the
size of the output (`max_size`), not by the size of the value: a value that shares substructure is written in full
(OQ-54). It recurses on the native stack, about 450 to 700 bytes a level, so the ceiling of 1000 levels takes at most
700 KB (a Windows main thread has 1 MiB: the test `test_a_value_nested_to_the_ceiling_is_encoded_on_a_small_native_stack`
runs it in CI on the three platforms).

## Tests

The oracle of the first release, a pure-Lua backend, is replaced by **expected-output fixtures** in `tests/fixtures`,
generated from that backend before it was deleted (the generator and the backend are in the git history, commit
`test(json): expected-output fixtures generated from the reference backend`): `decode_cases.lua` (texts with their
value or their failure), `encode_cases.lua` (values with their text or their failure: reason, message, path) and
`jcs_numbers.lua` (RFC 8785 numbers by bit pattern). They are edited by hand when a behaviour changes on purpose, never
regenerated. Besides: the behaviour tests of the public API (`decode_test.lua`, `encode_test.lua`, `errors_test.lua`),
property tests with no oracle (`roundtrip_test.lua`: `decode(encode(x)) == x`; `fuzz_test.lua`: mutated texts and
random values never crash, never produce invalid UTF-8 and round-trip; `HECATE_FUZZ_SECONDS` and `HECATE_FUZZ_SEED`
for a longer search), `tonumber` of Lua as the reference for number literals, the RFC 8785 appendix B vectors, and the
JSONTestSuite corpus (`lua tools/run.lua fetch-fixtures json`).

## Layout

```text
src/hecate/json/init.lua   public entry point
src/hecate/json/errors.lua error classes
src/hecate/json/internal/  markers, backend seam (loads the native modules), error positions
tests/unit/  tests/fixtures/ expected outputs; tests/external.lua pins the corpus
examples/    tested examples of the reference pages
csrc/        C decoder (vendored yyjson in csrc/vendor)
native/      Rust encoder (Cargo crate)
```
