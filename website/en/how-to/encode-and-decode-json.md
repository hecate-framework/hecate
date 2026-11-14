---
description: Encode and decode JSON with hecate.json, keep integers and floats apart, write null and empty arrays, bound hostile input and read decode errors.
hecate: "0.x"
lua: "5.5"
order: 6
---

# Encode and decode JSON

This guide shows how to read and write JSON text ([RFC 8259](https://www.rfc-editor.org/rfc/rfc8259)) with
`hecate.json`. It is written for hecate 0.x and Lua 5.5.

`hecate.json` has no pure-Lua fallback: it needs its native module. In a clone of the repository, build it once with
`lua tools/run.lua build-native json`.

## Decode a text

`json.decode(text, options?)` turns a JSON text into a Lua value.

<!-- example: packages/json/examples/hecate.json.decode.lua -->
```lua
-- Decoding returns Lua integers for integer literals and floats otherwise; `[]`
-- and `{}` keep their kind through markers, so an empty array round-trips.
local json = require("hecate.json")

local value = json.decode('{"count":3,"ratio":0.5,"items":[]}')
print(("%s %s %s %s"):format(math.type(value.count), math.type(value.ratio), json.is_array(value.items), json.encode(value.items)))
-- Prints: integer float true []
```

Numbers keep their kind. An integer literal becomes a Lua integer, and any other number becomes a float.

An empty `[]` and an empty `{}` look the same in Lua: an empty table. So `decode` marks each array and each object.
`json.is_array(value)` and `json.is_object(value)` read the mark, and `encode` uses it to write the same text back.

## Bound hostile input

Two options of `decode` bound what an untrusted text can cost:

| Option | Default | Bounds |
|---|---|---|
| `max_depth` | 1000 | the nesting of arrays and objects, from 1 to 1000 |
| `max_size` | 16 MiB | the length of the text, in bytes |

A text beyond a bound raises a `DecodeError`:

```lua
local json = require("hecate.json")

local ok, err = pcall(json.decode, "[[1]]", { max_depth = 1 })
print(ok, err.context.reason)
-- Prints: false	depth_limit
ok, err = pcall(json.decode, "[1, 2, 3]", { max_size = 4 })
print(ok, err.context.reason)
-- Prints: false	size_limit
```

The default of `max_depth` is also its ceiling: you can lower it, never raise it. Raise `max_size` only for trusted
text.

## Encode a value

`json.encode(value, options?)` turns a Lua value into compact JSON text.

<!-- example: packages/json/examples/hecate.json.encode.lua -->
```lua
-- Encoding keeps the difference between integers and floats, writes `json.null`
-- explicitly, and orders members with `canonical` so that the text is stable.
local json = require("hecate.json")

print(json.encode({ b = 1, a = 2.0, c = json.null }, { canonical = true }))
-- Prints: {"a":2.0,"b":1,"c":null}
```

A float is always written with a point or an exponent. So `2.0` stays a float when the text is decoded again, and `1`
stays an integer.

### Write null and empty arrays

Lua cannot hold a `nil` at the end of a table, so `encode` cannot see it. Write `json.null` for a JSON `null`.

An empty table has no element to tell its kind, and `encode` writes it as an object. Mark an empty array with
`json.array()`, or an empty object with `json.object()`:

```lua
local json = require("hecate.json")

local order = { id = 7, note = json.null, lines = json.array() }
print(json.encode(order, { canonical = true }))
-- Prints: {"id":7,"lines":[],"note":null}
print(json.encode({}))
-- Prints: {}
```

### Format and order the text

- `pretty = true` writes one member or element per line, indented by two spaces.
- `indent` sets the indentation: a number of spaces, or a string of spaces and tabs. It implies `pretty`.
- `canonical = true` orders the members of every object by the UTF-16 code units of their names
  ([RFC 8785](https://www.rfc-editor.org/rfc/rfc8785)), so the same value always gives the same text.

```lua
local json = require("hecate.json")

print(json.encode({ 1, 2 }, { indent = 4 }))
-- Prints: [
--     1,
--     2
-- ]
```

Without `canonical`, the members of an object are written in no defined order.

For signing or hashing, `canonical = "rfc8785"` writes the full JSON Canonicalization Scheme.

## Read a decode error

A text that `decode` rejects raises a `DecodeError`. Its context says why, in `context.reason`, and where, as
`offset`, `line` and `column`.

<!-- example: packages/json/examples/hecate.json.DecodeError.lua -->
```lua
-- A rejected text raises a `DecodeError` whose context names the reason and the
-- position.
local json = require("hecate.json")

local ok, err = pcall(json.decode, "[1, 2")
print(("%s %s %d %d"):format(ok, err.context.reason, err.context.line, err.context.column))
-- Prints: false syntax 1 6
```

`decode` also rejects some texts that RFC 8259 permits, because parsers disagree on them:

- duplicate member names;
- lone surrogates;
- a byte order mark;
- numbers outside the double range.

Three reasons carry no position:

- `duplicate_member_name`: the parser (yyjson) keeps no position for it;
- `size_limit`: the whole text is too long;
- `out_of_memory`: the decoder could not allocate memory. That is a resource failure, not a defect of the text.

The table of reasons and what to do about each is in the
[package README](https://github.com/hecate-framework/hecate/blob/main/packages/json/README.md).

## See also

- Reference: [`hecate.json`](../reference/json/index.md), [`DecodeError`](../reference/json/DecodeError.md).
