---
description: Put UTF-8 strings in Normalization Form C or D with hecate.unicode, compare names that look the same, read the errors and know which Unicode version is in use.
hecate: "0.x"
lua: "5.5"
order: 22
---

# Normalise Unicode strings

This guide shows how to compare and store text that can be spelled in more than one way, with `hecate.unicode`. It is
written for hecate 0.x and Lua 5.5.

The same visible text can be several byte strings. "café" can end with the letter U+00E9, or with the letter `e`
followed by the combining accent U+0301. A file system on macOS writes the second form, one on Linux keeps what it
was given. Two strings that mean the same text are *canonically equivalent* (Unicode Standard, section 3.7); the
*normalization forms* pick one spelling for each class of equivalent strings (UAX #15).

`hecate.unicode` provides the two canonical forms. Its tables come from the rock `hecate-unicode-data`, so the Unicode
version is the one of that rock, not of the framework.

## Compare names in Normalization Form C

`unicode.nfc(text)` returns the composed form: a letter and its marks become the precomposed letter when one exists.
Normalise both sides before you compare, or normalise once before you store:

<!-- example: packages/unicode/examples/hecate.unicode.nfc.lua -->
```lua
-- "café" typed with a letter and a combining accent, and "café" with one
-- precomposed letter, are two byte strings. In Normalization Form C they are
-- one, so they can be compared, stored and used as keys.
local unicode = require("hecate.unicode")

local typed = "cafe\u{301}"
local stored = "caf\u{E9}"
print(("%s %s"):format(typed == stored, unicode.nfc(typed) == unicode.nfc(stored)))
-- Prints: false true
```

It works for every script that has a composition in the Unicode Character Database: Latin with several marks,
Cyrillic, Greek with tonos, Hangul, and the compatibility singletons such as the angstrom sign (U+212B), which becomes
the letter U+00C5. A string that has only ASCII characters is returned as it is, without a copy.

Several combining marks on one letter are put in *canonical order* first, so the order in which a keyboard produced
them does not matter: `a`, U+0301, U+0323 and `a`, U+0323, U+0301 give the same string.

A code point that the Unicode version in use does not assign passes through unchanged.

## Decompose with Normalization Form D

`unicode.nfd(text)` returns the decomposed form: each letter is split into its base and its marks, in canonical order.
A Hangul syllable becomes its conjoining jamo by arithmetic:

<!-- example: packages/unicode/examples/hecate.unicode.nfd.lua -->
```lua
-- Normalization Form D splits a letter into its base and its marks. A Hangul
-- syllable becomes its conjoining jamo, computed and not looked up.
local unicode = require("hecate.unicode")

local syllable = "\u{AC01}"
print(("%d %d"):format(utf8.len(syllable), utf8.len(unicode.nfd(syllable))))
-- Prints: 1 3
```

`unicode.is_nfc(text)` and `unicode.is_nfd(text)` tell whether a string is already in a form. They normalise and
compare, so they cost as much as `nfc` and `nfd`.

## Read an error

A string that is not well-formed UTF-8 (a stray byte, an overlong form, a surrogate) raises an `InvalidUtf8Error`.
Its `context.position` is the 1-based byte of the first byte that is not valid:

<!-- example: packages/unicode/examples/hecate.unicode.InvalidUtf8Error.lua -->
```lua
-- A string that is not well-formed UTF-8 raises an error object of the Hecate
-- hierarchy; `context.position` is the 1-based byte of the first invalid byte.
local unicode = require("hecate.unicode")

local ok, err = pcall(unicode.nfc, "caf\xE9")
---@cast err any
print(("%s %s %d"):format(ok, err.code, err.context.position))
-- Prints: false hecate.unicode.InvalidUtf8Error 4
```

A value that is not a string raises an `ArgumentError`. If the installed `hecate-unicode-data` has a table layout that
this version of `hecate-unicode` does not know, the first call raises a `DataFormatError` that names both versions.

## Know and change the Unicode version

`unicode.unicode_version` is the Unicode version of the installed tables, for example `"18.0.0"`. To use a newer Unicode
version, install a newer `hecate-unicode-data`; nothing else changes:

```sh
luarocks install hecate-unicode-data
```

The Unicode normalization stability policy guarantees that the form of a string made of already assigned characters
never changes. Processes that run on different versions of the data agree on every such string; they differ only on a
character that the newer version assigns, which the older version leaves unchanged. A rolling upgrade needs no
coordination, and nothing you store depends on the version.

There is no setting to replace the tables at run time. `hecate-unicode-data` is released under the Unicode License
v3, `hecate-unicode` under the MIT licence.

## What is not provided

The compatibility forms (NFKC and NFKD), case mapping and case folding, grapheme and word segmentation and collation
are not part of `hecate.unicode`. The decision is recorded in ADR 0032 of the repository.
