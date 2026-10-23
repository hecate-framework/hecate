---
description: Encode and decode JSON with hecate.json, keep integers and floats apart, write null and empty arrays, and read decode errors.
hecate: "0.x"
lua: "5.5"
order: 6
---

# Encode and decode JSON

This guide shows how to read and write JSON text (RFC 8259) with `hecate.json`. It is written for
hecate 0.x and Lua 5.5.

## Decode a text

`json.decode(text, options?)` returns a Lua value. An integer literal becomes a Lua integer, any
other number a float, and an empty `[]` or `{}` keeps its kind through a marker, so it encodes
back to the same text.

<!-- example: packages/json/examples/hecate.json.decode.lua -->
```lua
-- Decoding returns Lua integers for integer literals and floats otherwise; `[]`
-- and `{}` keep their kind through markers, so an empty array round-trips.
local json = require("hecate.json")

local value = json.decode('{"count":3,"ratio":0.5,"items":[]}')
print(("%s %s %s %s"):format(math.type(value.count), math.type(value.ratio), json.is_array(value.items), json.encode(value.items)))
-- Prints: integer float true []
```

`max_depth` and `max_size` bound hostile input. Raise them only for trusted text.

## Encode a value

`json.encode(value, options?)` writes compact text; `pretty` and `indent` format it. A float is
always written with a point or an exponent, so `2.0` stays a float. Use `json.null` for a JSON
`null` (a `nil` cannot be seen at the end of a Lua table), and `json.array` or `json.object` to
mark an empty table. `canonical = true` orders members by UTF-16 code units (RFC 8785).

<!-- example: packages/json/examples/hecate.json.encode.lua -->
```lua
-- Encoding keeps the difference between integers and floats, writes `json.null`
-- explicitly, and orders members with `canonical` so that the text is stable.
local json = require("hecate.json")

print(json.encode({ b = 1, a = 2.0, c = json.null }, { canonical = true }))
-- Prints: {"a":2.0,"b":1,"c":null}
```

For signing or hashing, `canonical = "rfc8785"` writes the full JSON Canonicalization Scheme.

## Read a decode error

`decode` rejects some texts that RFC 8259 permits, because parsers disagree on them: duplicate
member names, lone surrogates, a byte order mark and numbers outside the double range. The
`DecodeError` says why and where: `context.reason`, and the position as `offset`, `line` and
`column`. A duplicate member name has no position when the native decoder is used: its parser
(yyjson) does not keep one.

<!-- example: packages/json/examples/hecate.json.DecodeError.lua -->
```lua
-- A rejected text raises a `DecodeError` whose context names the reason and the
-- position.
local json = require("hecate.json")

local ok, err = pcall(json.decode, "[1, 2")
print(("%s %s %d %d"):format(ok, err.context.reason, err.context.line, err.context.column))
-- Prints: false syntax 1 6
```

The table of reasons and what to do about each is in the
[package README](https://github.com/hecate-framework/hecate/blob/main/packages/json/README.md).

Reference: [`hecate.json`](../reference/json/index.md), [`DecodeError`](../reference/json/DecodeError.md).
