-- The examples included in the documentation are tested files: each one runs without error, and what a line
-- prints is written in a `-- Prints:` block directly under that line (the shared runner
-- `tools/harness/examples.lua` checks both; `docs/architecture/documentation.md`, "Code examples").
local test = require("harness.test")
local examples = require("harness.examples")
local T = test.Case("ExamplesTest")

local here = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
local directory = here:match("^(.*)/tests/unit/") .. "/examples"
local NAMES = {
  "hecate.schema.validate",
  "hecate.schema.Schema.check",
  "hecate.schema.to_json_schema",
  "hecate.schema.string",
  "hecate.schema.integer",
  "hecate.schema.map",
  "hecate.schema.enumeration",
  "hecate.schema.tagged_union",
  "hecate.schema.union",
  "hecate.schema.of",
  "hecate.schema.Schema.build",
  "hecate.schema.Schema.represent",
  "hecate.schema.default",
  "hecate.schema.sent",
}

function T:test_every_example_runs_and_prints_what_it_says()
  examples.check(self, directory, NAMES)
end

return T
