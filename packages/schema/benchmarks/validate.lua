-- Micro-benchmark: compiled validators of `schema` (validate, coerce, build) on a record of nested
-- objects, an array of 100 such records, and a union of two object shapes.
-- Usage: lua packages/schema/benchmarks/validate.lua   (from the repository root)
global <const> _VERSION, package, os, string, print, require, table, ipairs
package.path = "packages/schema/src/?.lua;packages/schema/src/?/init.lua;packages/json/src/?.lua;"
  .. "packages/json/src/?/init.lua;packages/core/src/?.lua;packages/core/src/?/init.lua;" .. package.path
local version = _VERSION:match("%d+%.%d+")
for _, tree in ipairs({ ".hecate/rocks", "spikes/rocks" }) do
  package.cpath = tree .. "/lib/lua/" .. version .. "/?.so;" .. package.cpath
end

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

local function report(label, schema_, value, method)
  local seconds = time(function()
    for _ = 1, ITERATIONS do schema_[method](schema_, value) end
  end)
  print(("%s %s %.0f operations/s"):format(method, label, ITERATIONS / seconds))
end

for _, method in ipairs({ "validate", "coerce" }) do
  report("record", record, single, method)
  report("array-of-100", records, list, method)
  report("union", shape, tagged, method)
end
report("record", record, single, "build")
