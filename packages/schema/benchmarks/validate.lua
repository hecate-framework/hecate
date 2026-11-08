-- Micro-benchmark: compiled validators of `schema` (validate, coerce, build, represent) on a record of nested
-- objects, an array of 100 such records, a union of two object shapes, a tagged union, a class-bound build, a recursive
-- union of two classes of identical shape, a failing input, a string with a length and a format, and `build` with
-- `coerce = true`.
-- Usage: lua packages/schema/benchmarks/validate.lua   (from the repository root)
global <const> _VERSION, package, os, string, print, require, table, ipairs
package.path = "packages/schema/src/?.lua;packages/schema/src/?/init.lua;packages/json/src/?.lua;"
  .. "packages/json/src/?/init.lua;packages/core/src/?.lua;packages/core/src/?/init.lua;" .. package.path
local version = _VERSION:match("%d+%.%d+")
for _, tree in ipairs({ ".hecate/rocks", "spikes/rocks" }) do
  package.cpath = tree .. "/lib/lua/" .. version .. "/?.so;" .. package.cpath
end

local core = require("hecate.core")
local schema = require("hecate.schema")

local ROUNDS = 7
local ITERATIONS = 2000

local record = schema.object({
  id = schema.integer({ minimum = 1 }),
  name = schema.string({ min_length = 1, max_length = 64 }),
  score = schema.number({ minimum = 0 }),
  active = schema.boolean(),
  nickname = schema.optional(schema.string()),
  tags = schema.array(schema.string(), { max_items = 16 }),
  position = schema.object({ x = schema.number(), y = schema.number() }),
})
local records = schema.array(record)
local shape = schema.union({
  schema.object({ kind = schema.literal("a"), value = schema.integer() }),
  schema.object({ kind = schema.literal("b"), value = schema.string() }),
})

local function make(i)
  return {
    id = i, name = "record " .. i, score = i / 3, active = i % 2 == 0, tags = { "x", "y" },
    position = { x = i / 7, y = i / 11 },
  }
end
local list = {}
for i = 1, 100 do list[i] = make(i) end
local single = make(1)
local tagged = { kind = "b", value = "text" }

--- Median seconds of ROUNDS runs of f.
local function time(f)
  local samples = {}
  f()
  for i = 1, ROUNDS do
    local start = os.clock()
    f()
    samples[i] = os.clock() - start
  end
  table.sort(samples)
  return samples[(ROUNDS + 1) // 2]
end

--- `extra` is the optional third argument of the method (the options of `build`); `name` labels it in the output.
local function report(label, schema_, value, method, extra, name)
  local seconds = time(function()
    for _ = 1, ITERATIONS do schema_[method](schema_, value, extra) end
  end)
  print(("%s %s %.0f operations/s"):format(name or method, label, ITERATIONS / seconds))
end

for _, method in ipairs({ "validate", "coerce" }) do
  report("record", record, single, method)
  report("array-of-100", records, list, method)
  report("union", shape, tagged, method)
end
report("record", record, single, "build")

-- Represent of a record (the plain, JSON-ready form).
report("record", record, single, "represent")
report("array-of-100", records, list, "represent")

-- Class-bound build through `schema.of`.
local Person = core.class("BenchPerson")
function Person.schema()
  return schema.object({
    id = schema.integer({ minimum = 1 }), name = schema.string({ min_length = 1 }),
  })
end
core.finalise(Person)
local Address = core.class("BenchAddress")
function Address.schema() return schema.object({ city = schema.string(), zip = schema.string() }) end
core.finalise(Address)
local person = schema.of(Person)
local person_content = { id = 1, name = "Ada" }
report("class-bound", person, person_content, "build")
local Host = core.class("BenchHost")
function Host.schema()
  return schema.object({ id = schema.integer(), address = schema.of(Address) })
end
core.finalise(Host)
local host = schema.of(Host)
report("class-bound-nested", host, { id = 1, address = { city = "Paris", zip = "75001" } }, "build")

-- Tagged union.
local events = schema.tagged_union("type", {
  created = schema.object({ id = schema.integer() }),
  renamed = schema.object({ id = schema.integer(), name = schema.string() }),
})
local event = { type = "renamed", id = 1, name = "x" }
report("tagged-union", events, event, "validate")
report("tagged-union", events, event, "build")
report("tagged-union", events, event, "represent")

-- Recursive union of two classes of identical shape (the memoisation probe of OQ-91), depth 30: linear.
local function twins(depth, innermost)
  local P, Q = core.class("BenchTwinP"), core.class("BenchTwinQ")
  local of_p, of_q = schema.of(P), schema.of(Q)
  local function body()
    return schema.object({ value = schema.optional(schema.string()),
      next = schema.optional(schema.union({ of_p, of_q })) })
  end
  function P.schema() return body() end
  function Q.schema() return body() end
  core.finalise(P)
  core.finalise(Q)
  local value = { value = innermost }
  for _ = 2, depth do value = { next = value } end
  return of_p, value
end
local twin_schema, twin_invalid = twins(30, 1)
local _, twin_valid = twins(30, "ok")
report("twins-30-invalid", twin_schema, twin_invalid, "validate")
report("twins-30-valid", twin_schema, twin_valid, "validate")

-- A failing input: several violations, and a union whose detail pass runs.
local failing = { id = 0, name = "", score = -1, active = "yes", tags = { 1, 2 }, position = { x = "a" }, extra = true }
report("failing-record", record, failing, "validate")
report("failing-union", shape, { kind = "c", value = 1 }, "validate")

-- A string with a length and a format.
local email = schema.string({ min_length = 3, max_length = 64, format = "email" })
report("string-email", email, "someone@example.com", "validate")
local text = schema.string({ min_length = 1, max_length = 64 })
report("string-length", text, "hello world", "validate")

-- `build` with `coerce = true` (content read from text).
local coerce_options = { coerce = true }
local query = schema.object({ id = schema.integer(), score = schema.number(), active = schema.boolean(),
  tags = schema.array(schema.string()) })
report("query", query, { id = "42", score = "1.5", active = "true", tags = "a,b,c" }, "build", coerce_options,
  "build-coerce")

-- A map of 20 integers read from text (the coercer of a map visits its members in key order when one fails).
local counts = schema.map(schema.integer())
local texts, numbers = {}, {}
for i = 1, 20 do texts["key" .. i] = ("%d"):format(i); numbers["key" .. i] = i end
report("map-of-20", counts, texts, "coerce")
report("map-of-20", counts, numbers, "validate")
