# `hecate-unicode`

> Unicode normalisation of UTF-8 strings: NFC, NFD, Hangul syllable arithmetic and canonical reordering.

| | |
|---|---|
| Module | `hecate.unicode` |
| Rock | `hecate-unicode` |
| Layer | 0 — Foundation |
| Roadmap phase | 3 |
| Status | alpha — NFC and NFD conformant with `NormalizationTest.txt` of the pinned Unicode version (100% of the NFC and NFD columns) |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`unicode-data`](../unicode-data) (>= 18.0.0) |
| Used by | `doc` |
| Native code | none |
| Specification | [ADR 0032](../../docs/adr/0032-unicode-normalisation-packages.md); Unicode Standard 3.11 and 3.12; [UAX #15](https://www.unicode.org/reports/tr15/) |
| Decisions | [ADR 0032](../../docs/adr/0032-unicode-normalisation-packages.md), [ADR 0018](../../docs/adr/0018-error-signalling.md) |
| Agent | [`pkg-unicode`](../../.claude/agents/pkg-unicode.md) |
| Repository | read-only mirror `hecate-framework/hecate-unicode`, generated from this directory (ADR 0017) |

## Responsibilities

- `nfc` and `nfd` of UTF-8 strings: full canonical decomposition, canonical ordering by combining class (a stable sort,
  n log n on a long run of marks), canonical composition with the blocking rule (UAX #15)
- the Hangul syllable arithmetic (Unicode Standard 3.12), computed and not in the tables
- `is_nfc` and `is_nfd`, which normalise and compare (they cost as much as `nfc` and `nfd`)
- `unicode.unicode_version`, the Unicode version of the installed `hecate-unicode-data`, and `unicode.version`, the version of the package
- invalid UTF-8 and a table layout that this version does not know are error objects of the Hecate hierarchy
  (ADR 0018)

## Non-goals

- NFKC and NFKD (they need the compatibility mappings; additive later in the same data rock), case mapping and case
  folding, grapheme and word segmentation, collation, identifier profiles
- any I/O, any process-wide state other than the tables loaded on first use

## Standards and references

- Unicode Standard, section 3.11 "Normalization Forms" (canonical ordering D109, composition D115 to D117) and section 3.12
  "Conjoining Jamo Behavior"
- [UAX #15](https://www.unicode.org/reports/tr15/) Unicode Normalization Forms; the Normalization Stability Policy
- `NormalizationTest.txt` of the Unicode Character Database (conformance, not vendored)

## Public API

All names are fields of `require "hecate.unicode"`.

| Name | Description |
|---|---|
| `nfc(text)` | Normalization Form C of well-formed UTF-8 text; ASCII is returned as it is |
| `nfd(text)` | Normalization Form D |
| `is_nfc(text)`, `is_nfd(text)` | whether `text` is in the form |
| `unicode_version` | the Unicode version of the tables, for example `"18.0.0"` |
| `version` | the version of this package, the version of Hecate (`VERSION`, ADR 0005) |
| `UnicodeError` | root of the errors of this package (`hecate.unicode.UnicodeError`) |
| `InvalidUtf8Error` | the string is not well-formed UTF-8; `context.position` is the 1-based byte of the first invalid one |
| `DataFormatError` | the installed `hecate-unicode-data` has a table layout (`format`) unknown to this version; `context.format`, `context.supported`, `context.unicode_version` |

A value that is not a string raises `core.ArgumentError`. Code points that the Unicode version in use does not assign
pass through unchanged.

```lua
local unicode = require("hecate.unicode")

assert(unicode.nfc("cafe\u{301}") == "caf\u{E9}")
assert(unicode.nfd("\u{AC01}") == "\u{1100}\u{1161}\u{11A8}")
```

## The Unicode version and the data rock

The tables are the rock `hecate-unicode-data`, versioned by the Unicode version (`18.0.0-1`), released on the Unicode
schedule and not with the framework (ADR 0032). This package declares `hecate-unicode-data >= 18.0.0`: no exact pin, no
upper bound. Upgrade Unicode with `luarocks install hecate-unicode-data`; nothing else changes. There is no setting,
variable or `package.loaded` convention to replace the tables at run time.

Upgrading is safe and a mixed fleet is harmless. By the Unicode Normalization Stability Policy, the decomposition,
combining class and composition of an assigned character never change, so a string made of characters that the older
version assigns normalises identically under every later version. Two processes on different versions disagree only on a
string that holds a code point assigned in the newer version: in the older process that code point is unassigned (class
0, no decomposition) and passes through unchanged. Nothing cached or stored depends on the version, so a rolling upgrade
needs no coordination.

`hecate.unicode` checks the integer `format` of the data when it first loads the tables and refuses a layout it does not
know with a `DataFormatError`. The layout stays stable for the life of a Hecate major version.

## Measures

On Linux, Lua 5.5, x86-64: `require "hecate.unicode"` takes about 2 ms and 175 KiB; the first call loads and expands the
tables in about 2 ms and 270 KiB; `nfc` of mostly-Latin text runs at about 5 MB/s. Both tables are loaded once, on
first use.

## Tests

`tests/unit/` (composition, Hangul, reordering and blocking, the gaps of the former Latin table, invalid UTF-8, the
layout check, the examples of the documentation) and `tests/conformance/normalization_test.lua`: every line of every
part of `NormalizationTest.txt` (downloaded by `lua tools/run.lua fetch-fixtures unicode`, pinned by SHA-256 in
`tests/external.lua`), 100% of the NFC and NFD columns, idempotence, and the invariance of every code point that Part 1
does not list. Without the file the suite skips locally and fails in CI.

## Layout

```text
src/hecate/unicode/init.lua              public entry point
src/hecate/unicode/errors.lua            error classes
src/hecate/unicode/internal/             algorithm, hangul, tables (loading, format check)
tests/unit/  tests/conformance/  tests/external.lua
examples/                                the tested examples of the website
```
