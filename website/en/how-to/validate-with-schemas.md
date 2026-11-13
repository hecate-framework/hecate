---
description: Declare schemas with hecate.schema, validate and coerce values with JSON Pointer error paths, build instances of your classes, and emit JSON Schema 2020-12.
hecate: "0.x"
lua: "5.5"
order: 7
---

# Validate values with schemas

This guide shows how to declare a [schema](../reference/glossary.md#types-and-validation), validate a value against it, convert the
texts of a request, build instances of your classes and emit the matching JSON Schema document with
`hecate.schema`. It is written for hecate 0.x and Lua 5.5. To understand why schemas work this way,
read [Schemas and contracts](../explanation/schemas-and-contracts.md).

## Declare and validate

A schema is an immutable value built from constructors (`string`, `integer`, `object`, `array`,
`optional`, `union`, ...) with refinements as options. `validate` collects every
[violation](../reference/glossary.md#types-and-validation); the `path` of each one is an RFC 6901 JSON Pointer.

<!-- example: packages/schema/examples/hecate.schema.validate.lua -->
```lua
-- Declare a schema once, then validate a value: every violation is collected,
-- each with the JSON Pointer of the offending value.
local schema = require("hecate.schema")

local user = schema.object({
  name = schema.string({ min_length = 1 }),
  age = schema.integer({ minimum = 0 }),
})

local ok, violations = user:validate({ name = "", age = -1 })
assert(violations)
print(("%s %d %s %s"):format(tostring(ok), #violations, violations[1].path, violations[2].path))
-- Prints: false 2 /age /name
```

Undeclared properties of an `object` are rejected (violation `additional_properties`) unless the option
`additional_properties = true` says otherwise. The violation codes are stable; the list is in the
[specification](https://github.com/hecate-framework/hecate/blob/main/docs/architecture/schemas-and-contracts.md#violation-codes).

`check(value)` is the raising form of `validate`: it returns the value when it conforms, and raises a
`ValidationError` whose `context.violations` holds the same list otherwise. `coerce` and `build` do not raise: they
return two values, `true` and the result, or `false` and the list of violations.

### Report violations to a client

A client needs the JSON Pointer of each wrong value, a stable code and a message, not a Lua error. `check` raises a
`ValidationError`; turn `context.violations` into the plain table of a problem details response (RFC 9457) with
one entry per violation. The `message` of a violation never contains the value the client sent, so it is safe to
return. The kernel does this conversion for you; the example shows what it sends.

<!-- example: packages/schema/examples/hecate.schema.Schema.check.lua -->
```lua
-- Report violations to a client: `check` raises a `ValidationError`, and its
-- violations become the plain table of a problem details response (the kernel
-- does this conversion for you).
local core = require("hecate.core")
local schema = require("hecate.schema")

local user = schema.object({
  name = schema.string({ min_length = 1 }),
  age = schema.integer({ minimum = 0 }),
})

local ok, err = pcall(user.check, user, { name = "", age = -1 })
print(ok, core.is_instance_of(err, core.ValidationError))
-- Prints: false	true

-- One entry per violation: the JSON Pointer of the value, the stable code and
-- the message (no client value in it).
local problem = { type = "about:blank", title = "The content is not valid", status = 400, errors = {} }
for _, violation in ipairs(err.context.violations) do
  problem.errors[#problem.errors + 1] = { pointer = violation.path, code = violation.code, detail = violation.message }
end
for _, entry in ipairs(problem.errors) do
  print(entry.pointer, entry.code, entry.detail)
end
-- Prints: /age	minimum	the value is less than 0
-- /name	min_length	the string is shorter than 1

-- A conforming value is returned as it is.
print(user:check({ name = "Ada", age = 36 }).name)
-- Prints: Ada
```

## Give a class its schema

A class owns the name of its schema. Declare a class-level function `schema()` that returns the schema,
and use `schema.of(Class)` wherever the class is a part of another schema. To make the rule checkable,
declare the interface `schema.Representable`, which requires `schema`: `finalise` then raises a `ConformanceError` for a
class that declares it without a `schema` function. Declaring it is mandatory: `schema.of` refuses a class that does
not declare it, even when it has `schema()`, with an `ArgumentError` that names the class and the interface. The
refusal comes at declaration for a class that is already finalised, otherwise at first use. The emission puts the definition once in the root `$defs` under the name of the class and uses a
`$ref` at each use. Classes may refer to each other or to themselves.

<!-- example: packages/schema/examples/hecate.schema.of.lua -->
```lua
-- A class owns the schema of its instances: the interface
-- `schema.Representable` requires a class-level `schema()`, and
-- `schema.of(Class)` uses the class wherever it is a part of another schema.
local core = require("hecate.core")
local schema = require("hecate.schema")

local Representable = schema.Representable

local Address = core.class("Address", nil, { implements = { Representable } })
function Address.schema()
  return schema.object({ street = schema.string(), city = schema.string() })
end
core.finalise(Address)

local User = core.class("User", nil, { implements = { Representable } })
function User.schema()
  return schema.object({ name = schema.string(), address = schema.of(Address) })
end
core.finalise(User)

-- A class that declares the interface without `schema()` cannot be finalised.
local Incomplete = core.class("Incomplete", nil, { implements = { Representable } })
print((pcall(core.finalise, Incomplete)))
-- Prints: false

-- `schema.of` refuses a class that does not declare the interface, even when
-- it has a `schema` function.
local Plain = core.class("Plain")
function Plain.schema() return schema.object({}) end
core.finalise(Plain)
print((pcall(schema.of, Plain)))
-- Prints: false

local ok, user = schema.of(User):build({ name = "Ada", address = { street = "1 Main St", city = "Paris" } })
print(ok, core.is_instance_of(user, User), core.is_instance_of(user.address, Address))
-- Prints: true	true	true

-- The emission names each class once, in `$defs`, and refers to it.
local document = schema.of(User):to_json_schema()
print(document["$ref"], document["$defs"].User.properties.address["$ref"])
-- Prints: #/$defs/User	#/$defs/Address
```

## Build instances

`build(content, { method })` validates decoded JSON content and returns `true` and the value, or `false`
and the violations. A part declared with `schema.of(Class)` becomes an instance of its class, in
properties, arrays, maps and unions. The `init` of the class is not called. An absent attribute, or an
explicit `null`, is `nil` in the instance. When a class is a `value_class`, its instances are built frozen.

`method` is `"POST"` or `"PUT"` (strict, the default) or `"PATCH"`. The rule for a PATCH is in the next
sections.

### Build from path, query and header field texts

Query, path and header field values are texts. Pass `coerce = true` to convert them with the rules of `coerce`
and build the instances in one call. A text that cannot be converted gives the same `coercion` violation,
at the same path, as `coerce`. Defaults apply once, in the conversion, and never for a PATCH.
`schema.sent` records only the attributes the client provided. `coerce` must be a boolean.

<!-- example: packages/schema/examples/hecate.schema.Schema.build.lua -->
```lua
-- Build an instance of a class from the texts of a query string: convert,
-- validate, apply defaults.
local core = require("hecate.core")
local schema = require("hecate.schema")

local Filter = core.class("Filter", nil, { implements = { schema.Representable } })
function Filter.schema()
  return schema.object({
    status = schema.default(schema.string(), "open"),
    limit = schema.default(schema.integer({ minimum = 1, maximum = 100 }), 20),
    tags = schema.optional(schema.array(schema.string())),
    archived = schema.optional(schema.boolean()),
  })
end
core.finalise(Filter)

local filters = schema.of(Filter)

-- Every value of a query string is a text: `coerce = true` converts it
-- before building.
local _, filter = filters:build({ limit = "5", tags = "a,b", archived = "true" }, { coerce = true })
print(core.is_instance_of(filter, Filter), filter.status, filter.limit, #filter.tags, filter.archived)
-- Prints: true	open	5	2	true
print(schema.sent(filter, "limit"), schema.sent(filter, "status"))
-- Prints: true	false

-- A text that cannot be converted is a violation with the path of the
-- parameter.
local ok, violations = filters:build({ limit = "many" }, { coerce = true })
print(ok, violations[1].path, violations[1].code)
-- Prints: false	/limit	coercion
```

### Fill absent properties with defaults

`schema.default(inner, value)` makes a property optional. `coerce` (texts) and `build` (JSON content) give
an absent property a fresh deep copy of the default, so no table is shared between requests and the content
you passed is never modified. The default must conform to `inner`, checked at declaration. An explicit
`null` stays `null` and never takes the default. `validate` never supplies a value.

<!-- example: packages/schema/examples/hecate.schema.default.lua -->
```lua
-- A default makes a property optional. A POST or PUT receives a fresh copy of
-- it; a PATCH never does, because an absent attribute of a PATCH means
-- unchanged.
local core = require("hecate.core")
local schema = require("hecate.schema")

local Article = core.class("Article", nil, { implements = { schema.Representable } })
function Article.schema()
  return schema.object({
    title = schema.string(),
    tags = schema.default(schema.array(schema.string()), { "draft" }),
  })
end
core.finalise(Article)

local articles = schema.of(Article)

local _, created = articles:build({ title = "Hello" })
print(#created.tags, created.tags[1], schema.sent(created, "tags"))
-- Prints: 1	draft	false

-- The default is copied: changing it on one instance changes nothing else.
created.tags[1] = "changed"
local _, other = articles:build({ title = "Again" })
print(other.tags[1])
-- Prints: draft

local _, patched = articles:build({ title = "Renamed" }, { method = "PATCH" })
print(patched.tags, schema.sent(patched, "tags"))
-- Prints: nil	false

-- `validate` never supplies a value; it only checks.
print((schema.object({ tags = schema.default(schema.string(), "x") }):validate({})))
-- Prints: true
```

### Tell unchanged from cleared in a PATCH

In a PATCH, an absent attribute means unchanged and an explicit `null` means cleared. Both leave the
attribute `nil` in the instance, so `schema.sent(instance, name)` tells them apart. It is true when the
attribute was in the content, `null` included, and false for an attribute filled by a default. A PATCH
relaxes only the required properties of the top-level object. Nested objects stay strict, and a `null`
fails unless the property is `nullable`. A value that `build` did not make has sent nothing, and `sent`
returns false without raising.

<!-- example: packages/schema/examples/hecate.schema.sent.lua -->
```lua
-- For a PATCH, `schema.sent` tells an attribute left unchanged from one that
-- was cleared.
local core = require("hecate.core")
local json = require("hecate.json")
local schema = require("hecate.schema")

local Profile = core.class("Profile", nil, { implements = { schema.Representable } })
function Profile.schema()
  return schema.object({
    name = schema.string(),
    bio = schema.optional(schema.nullable(schema.string())),
  })
end
core.finalise(Profile)

local profiles = schema.of(Profile)

-- The attribute is absent: unchanged.
local _, unchanged = profiles:build({ name = "Ada" }, { method = "PATCH" })
print(unchanged.bio, schema.sent(unchanged, "bio"))
-- Prints: nil	false

-- The attribute is an explicit null: cleared. Both leave `bio` nil.
local _, cleared = profiles:build({ bio = json.null }, { method = "PATCH" })
print(cleared.bio, schema.sent(cleared, "bio"), schema.sent(cleared, "name"))
-- Prints: nil	true	false

-- A PATCH relaxes the required properties of the top-level object only.
print((profiles:build({}, { method = "POST" })))
-- Prints: false
print((profiles:build({}, { method = "PATCH" })))
-- Prints: true

-- A value that `build` did not make has sent nothing, and `sent` does not
-- raise.
print(schema.sent({ name = "Ada" }, "name"))
-- Prints: false
```

## Represent an instance in a response

`represent(value)` is the other direction of `build`: it turns an instance into plain values that
`json.encode` can write, its [representation](../reference/glossary.md#types-and-validation). `hecate.json` knows
nothing about classes, so the schema does the conversion. A class-bound part becomes a plain table of the
attributes its schema declares, and only those: an attribute the schema does not declare, such as a
`password`, never appears, even if the instance has it. A member of a `core` enumeration becomes its name.
Nested parts, arrays, maps, unions and tagged unions convert recursively, and an empty array still encodes as
`[]` and an empty map as `{}`.

`represent` does not validate: it trusts the value, because a response that does not conform is a bug of the
server (call `validate` where you want to check it). An absent attribute is omitted, `json.null` stays null, and
a default is never applied. An attribute that was sent as `null` (an instance made by `build`) comes back as `null`,
so the content round-trips. A method or a prototype field of the class never appears. The input is not modified and the
result shares no table with it. A union uses the
alternative that accepts the value, and raises `ValidationError` when none does. The nesting guard and the work
budget apply as for `validate`: a cycle in the object graph raises `ValidationError` whose violation has the code
`depth_limit` and the JSON Pointer where it stopped.

<!-- example: packages/schema/examples/hecate.schema.Schema.represent.lua -->
```lua
-- Represent an instance for a response: declared attributes only, enumeration
-- members as names, then encode.
local core = require("hecate.core")
local json = require("hecate.json")
local schema = require("hecate.schema")

local Status = core.enumeration("AccountStatus", { "active", "disabled" })

local Account = core.class("Account", nil, { implements = { schema.Representable } })
function Account.schema()
  return schema.object({
    name = schema.string(),
    status = schema.enumeration(Status),
    tags = schema.array(schema.string()),
  })
end
core.finalise(Account)

local accounts = schema.of(Account)
local _, account = accounts:build({ name = "Ada", status = "active", tags = {} })
-- Not declared by the schema: it never reaches the response.
account.password = "secret"

local plain = accounts:represent(account)
print(plain.status, plain.password, core.is_instance_of(plain, Account))
-- Prints: active	nil	false
print(json.encode(plain.tags), json.encode(plain.name))
-- Prints: []	"Ada"

-- A cycle in the object graph ends with an error that names the limit,
-- instead of a hang.
local Node = core.class("Node", nil, { implements = { schema.Representable } })
function Node.schema() return schema.object({ next = schema.optional(schema.of(Node)) }) end
core.finalise(Node)

local node = core.allocate(Node)
node.next = node
local ok, err = pcall(schema.of(Node).represent, schema.of(Node), node)
print(ok, err.context.violations[1].code)
-- Prints: false	depth_limit
```

## Emit JSON Schema

`to_json_schema()` returns a JSON Schema 2020-12 document as plain values.

<!-- example: packages/schema/examples/hecate.schema.to_json_schema.lua -->
```lua
-- The same schema emits a JSON Schema 2020-12 document, here to list its
-- required properties.
local schema = require("hecate.schema")

local user = schema.object({
  name = schema.string(),
  nickname = schema.optional(schema.string()),
})

local document = user:to_json_schema()
print(("%s %d"):format(document.type, #document.required))
-- Prints: object 1
```

Choices taken conservatively (for example, `integer` refuses `1.0`) are listed in the package
README and in the open questions.

## Edge cases

The sections below cover the options and constructs that behave in a way you may not expect.

### Constrain strings

`format` checks a well-known format: `uuid`, `date`, `date-time`, `email`, `ipv4` or `uri`. `pattern`
is a Lua pattern, not a regular expression. Validation uses it as written. The emission translates it
to an ECMA-262 regular expression for the contract. Lua patterns can backtrack, so anchor them with `^` and `$` and
declare `max_length`: without it, a string longer than 65536 bytes is not matched and gets a `pattern` violation with
`context.reason` set to `too_long_for_pattern`. A malformed pattern such as `ab%` is refused when you declare it.

<!-- example: packages/schema/examples/hecate.schema.string.lua -->
```lua
-- `format` checks well-known string formats. `pattern` is a Lua pattern,
-- translated to an ECMA-262 regular expression when the schema is emitted.
local schema = require("hecate.schema")

print((schema.string({ format = "email" }):validate("ada@example.org")))
-- Prints: true

local sku = schema.string({ pattern = "^%u%u%-%d+$" })
print((sku:validate("AB-42")), (sku:validate("ab-42")))
-- Prints: true	false
print(sku:to_json_schema().pattern)
-- Prints: ^[A-Z][A-Z]-[0-9]+$

-- A pattern that cannot be translated exactly is refused when emitting, never
-- approximated: `%b` and `%f`, and any non-ASCII byte.
for _, pattern in ipairs({ "%bxy", "%f[%w]", "caf\u{e9}" }) do
  local refused = schema.string({ pattern = pattern })
  print((pcall(refused.to_json_schema, refused)))
end
-- Prints: false
-- false
-- false

-- A `logger` reports the pattern at declaration instead.
schema.string({ pattern = "%bxy", logger = { warning = function(_, message) print(message) end } })
-- Prints: schema: pattern "%bxy" cannot be emitted: %b has no exact translation
```

The translation is exact for a defined subset and refuses the rest. The refused constructs are `%b`,
`%f`, the position capture `()` and any non-ASCII byte in the pattern. A schema with such a pattern still
validates in Lua, but `to_json_schema()` raises an `ArgumentError` that says so and how to rewrite the pattern:
use sets, classes, `format`, `min_length` or `enum`. Pass a `logger` (any object with a
`warning(message, fields)` method) to be told at declaration: the text of the warning carries the pattern and
the reason, and `fields` carries them too. The subset is in
[the specification](https://github.com/hecate-framework/hecate/blob/main/docs/architecture/schemas-and-contracts.md#the-pattern-option).

### Limit numbers and decimals

`integer` accepts only Lua integers, so `1.0` is refused. `multiple_of` takes a whole-number divisor
greater than zero. A fractional divisor such as `0.01` is refused at declaration, because binary floats
cannot express a decimal step: `19.99` would be rejected for `0.01`, while a validator with decimal
arithmetic accepts it, and the contract and the validator would disagree. To limit the decimal places,
choose one of two alternatives.

- Use an integer in minor units, for example cents, which is the right model for money.
- Use a string with a `pattern`, for example exactly two decimals. JSON Schema has no other keyword for a
  number of decimal places.

<!-- example: packages/schema/examples/hecate.schema.integer.lua -->
```lua
-- `multiple_of` takes a whole-number divisor. For decimal places, use minor
-- units or a string.
local schema = require("hecate.schema")

local lots = schema.integer({ multiple_of = 5 })
print((lots:validate(15)), (lots:validate(16)))
-- Prints: true	false

-- A fractional divisor is refused at declaration: binary floats cannot
-- express a decimal step.
local declared, err = pcall(schema.number, { multiple_of = 0.01 })
print(declared, tostring(err):match("ArgumentError: ([^;]+)"))
-- Prints: false	schema: number: option multiple_of must be a whole number

-- First alternative: an integer in minor units, here cents (1999 is 19.99).
local cents = schema.integer({ minimum = 0 })
print((cents:validate(1999)))
-- Prints: true

-- Second alternative: a string with exactly two decimals.
local price = schema.string({ pattern = "^%d+%.%d%d$" })
print((price:validate("19.99")), (price:validate("19.9")))
-- Prints: true	false
```

### Declare maps and enumerations

A `map` has string keys that are not known in advance and one schema for all the values. It takes no key
schema, because JSON object keys are always strings. `min_properties` and `max_properties` bound its size.

<!-- example: packages/schema/examples/hecate.schema.map.lua -->
```lua
-- A map has string keys that are not declared in advance, and one schema for
-- every value.
local schema = require("hecate.schema")

local stock = schema.map(schema.integer({ minimum = 0 }), { max_properties = 2 })

print((stock:validate({ apples = 3, pears = 0 })))
-- Prints: true

local _, violations = stock:validate({ apples = -1 })
local violation = assert(violations)[1]
print(violation.path, violation.code)
-- Prints: /apples	minimum

_, violations = stock:validate({ apples = 1, pears = 2, plums = 3 })
violation = assert(violations)[1]
print(violation.path == "", violation.code)
-- Prints: true	max_properties

-- The emission is an object whose `additionalProperties` is the schema of the
-- values.
print(stock:to_json_schema().additionalProperties.type)
-- Prints: integer
```

`schema.enumeration` also takes an enumeration of `hecate.core`. The JSON form of a member is its name, so
`validate` and `coerce` accept exactly the names and never a member object. `build` replaces a name by the
member, also inside objects, arrays and maps. A default is given as a name.

<!-- example: packages/schema/examples/hecate.schema.enumeration.lua -->
```lua
-- An enumeration of `core` is represented in JSON by the name of its members.
local core = require("hecate.core")
local schema = require("hecate.schema")

local Status = core.enumeration("Status", { "active", "disabled", "pending" })
local account = schema.object({ status = schema.enumeration(Status) })

print((account:validate({ status = "active" })))
-- Prints: true

-- Only the names are accepted, never the member itself.
local _, violations = account:validate({ status = "Active" })
local violation = assert(violations)[1]
print(violation.path, violation.code, table.concat(assert(violation.context).values, " "))
-- Prints: /status	enum	active disabled pending

-- `build` replaces the name by the member.
local _, built = account:build({ status = "disabled" })
print(built.status == Status.disabled)
-- Prints: true

local emitted = account:to_json_schema().properties.status
print(emitted.type, #emitted.enum)
-- Prints: string	3
```

### Choose between `union` and `tagged_union`

When the alternatives of a sum differ by a property that holds a constant (a `type` or `kind`
field), declare a `tagged_union`: the validator reads the tag once and validates only the selected
variant, with no re-validation. A violation inside the variant keeps its own path. A missing tag is a
`required` violation at the tag property, and an unknown or non-string tag is a `tagged_union` violation
that lists the variants in `context.values`.

<!-- example: packages/schema/examples/hecate.schema.tagged_union.lua -->
```lua
-- A tagged union reads the tag once and validates only the selected variant.
local schema = require("hecate.schema")

local shape = schema.tagged_union("kind", {
  circle = schema.object({ radius = schema.number({ exclusive_minimum = 0 }) }),
  rectangle = schema.object({ width = schema.number(), height = schema.number() }),
})

print((shape:validate({ kind = "circle", radius = 2 })))
-- Prints: true

-- The violations are those of the selected variant, at the path of the
-- offending value.
local _, violations = shape:validate({ kind = "circle", radius = -1 })
local violation = assert(violations)[1]
print(violation.path, violation.code)
-- Prints: /radius	exclusive_minimum

-- An unknown tag lists the variants; a missing tag is a missing property.
_, violations = shape:validate({ kind = "triangle" })
violation = assert(violations)[1]
print(violation.path, violation.code, table.concat(assert(violation.context).values, " "))
-- Prints: /kind	tagged_union	circle rectangle
_, violations = shape:validate({ radius = 2 })
violation = assert(violations)[1]
print(violation.path, violation.code)
-- Prints: /kind	required

-- The emission is a `oneOf` of the variants, each with the tag as a constant.
print(#shape:to_json_schema().oneOf)
-- Prints: 2
```

A union never accepts null on its own: `nullable` is the only way for a property to accept
`json.null`. `schema.union` refuses at declaration (an `ArgumentError`) every alternative that accepts null:
`schema.null()`, a `nullable` schema, `schema.literal(json.null)` or an enumeration containing `json.null`, also
under `named`, `optional` or `default`. Wrap the union instead,
as `nullable(union(...))`:

<!-- example: packages/schema/examples/hecate.schema.union.lua -->
```lua
-- A union never accepts null on its own: `nullable` is the only way for a
-- property to accept null.
local json = require("hecate.json")
local schema = require("hecate.schema")

local plain = schema.union({ schema.string(), schema.integer() })
print((plain:validate(json.null)))
-- Prints: false

-- A `null` or `nullable` alternative is refused at declaration, with a hint.
local ok, err = pcall(schema.union, { schema.string(), schema.null() })
print(ok, (err --[[@as table]]).code)
-- Prints: false	hecate.core.ArgumentError

-- Wrap the union instead.
local identifier = schema.nullable(plain)
print((identifier:validate(json.null)), (identifier:validate("a1")), (identifier:validate(true)))
-- Prints: true	true	false

-- `any` is different: it accepts every value, null included, by an explicit
-- choice.
print((schema.union({ schema.string(), schema.any() }):validate(json.null)))
-- Prints: true
```

`schema.any()` is not refused: it accepts every value, null included, as an explicit, different choice.

A `union` decides each alternative in turn (stopping at the first violation, literal properties first) and
remembers its answer for each table of the content during one call, so the work is proportional to the
tables times the unions. As a backstop, a call that needs more than 1,000,000 steps ends with a
`complexity_limit` violation at the path where it stopped. A failed `union` reports the violations of its
alternatives in `context.alternatives` only at the outermost union.

### Name a schema without a class

A schema that has neither a class nor a call to `named` is inlined and never receives a name.

For an inline schema that has no class, `schema.named("User", definition)` is the explicit opt-in: it
validates and coerces like `definition`, and the emission names it in the same way. A name is made of letters,
digits, `_`, `.` and `-`.

Two different definitions under one name in one emission raise an `ArgumentError` that names the colliding name
and says where each comes from: a class or `named`. This covers an inline name equal to the name of a
class. Equal definitions share one definition.
