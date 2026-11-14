---
description: Encode and decode JSON with hecate.json, keep integers and floats apart, write null and empty arrays, and read decode errors.
hecate: "0.x"
lua: "5.5"
order: 6
---

# Encode and decode JSON

`hecate.json` reads and writes JSON text (RFC 8259). Use it to turn a text into a Lua value and a Lua value into a
text, without losing the difference between an integer and a float, or between an empty array and an empty object.
This guide is written for hecate 0.x and Lua 5.5.

## Decode a text

`json.decode(text, options?)` returns a Lua value. Here is a text with an integer, a float and an empty array:

<!-- example: packages/json/examples/hecate.json.decode.lua -->
```lua
-- Decoding returns Lua integers for integer literals and floats otherwise; `[]`
-- and `{}` keep their kind through markers, so an empty array round-trips.
local json = require("hecate.json")

local value = json.decode('{"count":3,"ratio":0.5,"items":[]}')
print(("%s %s %s %s"):format(math.type(value.count), math.type(value.ratio), json.is_array(value.items), json.encode(value.items)))
-- Prints: integer float true []
```

Three rules explain the output.

- An integer literal becomes a Lua integer. Any other number becomes a float.
- A JSON `null` becomes the value `json.null`.
- An empty `[]` or `{}` keeps its kind through a marker. So it encodes back to the same text.

`decode` accepts two options that bound hostile input. `max_depth` is the deepest nesting accepted, from 1 to 1000
(default 1000). `max_size` is the longest text accepted, in bytes (default 16 MiB). The ceiling of `max_depth` is its
default, so you can only lower it. Raise `max_size` only for trusted text.

## Encode a value

`json.encode(value, options?)` returns compact text. Here it writes an integer, a float and a `null`:

<!-- example: packages/json/examples/hecate.json.encode.lua -->
```lua
-- Encoding keeps the difference between integers and floats, writes `json.null`
-- explicitly, and orders members with `canonical` so that the text is stable.
local json = require("hecate.json")

print(json.encode({ b = 1, a = 2.0, c = json.null }, { canonical = true }))
-- Prints: {"a":2.0,"b":1,"c":null}
```

Four details are worth knowing.

- A float is always written with a point or an exponent, so `2.0` stays a float.
- Use `json.null` for a JSON `null`. A `nil` cannot be told from a missing entry at the end of a Lua table.
- An empty table is written as an object. To write an empty array, mark the table with `json.array()`. To say
  "object" explicitly, use `json.object()`.
- Members of an object are written in no defined order, unless you set `canonical`.

`canonical = true` orders the members of every object by the UTF-16 code units of their names, as RFC 8785 does.
The numbers keep the codec's own format.

`pretty = true` writes one member or element per line, indented by 2 spaces. `indent` sets the indentation, as a
number of spaces or a string of spaces and tabs, and implies `pretty`.

`encode` has the same `max_depth` and `max_size` options as `decode`. The same defaults apply (1000 and 16 MiB).

### Sign or hash a text

For signing or hashing, `canonical = "rfc8785"` writes the full JSON Canonicalization Scheme. The text is compact, so
combining it with `pretty` or `indent` raises `ArgumentError`. Every number is written as an IEEE double, so an
integer beyond +-2^53 raises an `EncodeError` with the reason `integer_out_of_range`.

## Read a decode error

A text that `decode` rejects raises a `DecodeError`. Its `context` says why and where:

- `reason`: a short code such as `syntax` or `depth_limit`;
- `offset`: the number of bytes before the offending byte, counted from 0;
- `line` and `column`: the position, counted from 1 (the column in characters, not bytes).

Here the text stops before the closing bracket:

<!-- example: packages/json/examples/hecate.json.DecodeError.lua -->
```lua
-- A rejected text raises a `DecodeError` whose context names the reason and the
-- position.
local json = require("hecate.json")

local ok, err = pcall(json.decode, "[1, 2")
print(("%s %s %d %d"):format(ok, err.context.reason, err.context.line, err.context.column))
-- Prints: false syntax 1 6
```

Some positions do not exist. A duplicate member name has none, because the parser (yyjson) does not keep one. Nor do
`size_limit` (the whole text is too long) and `out_of_memory` (the decoder could not allocate memory: a resource
failure, not a defect of the text). For these three reasons, `offset`, `line` and `column` are absent.

`decode` also rejects some texts that RFC 8259 permits, because parsers disagree on them:

- duplicate member names;
- lone surrogates;
- a byte order mark;
- numbers outside the double range.

The table of reasons, and what to do about each, is in the
[package README](https://github.com/hecate-framework/hecate/blob/main/packages/json/README.md).

Reference: [`hecate.json`](../reference/json/index.md), [`DecodeError`](../reference/json/DecodeError.md).
