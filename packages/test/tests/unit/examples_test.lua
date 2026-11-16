-- The examples included in the website pages are tested files: each one runs without error, and what a line
-- prints is written in a `-- Prints:` block directly under that line (the shared runner
-- `tools/harness/examples.lua`; `docs/architecture/documentation.md`, "Code examples").
local test = require("harness.test")
local examples = require("harness.examples")
local T = test.Case("ExamplesTest")

local here = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
local directory = here:match("^(.*)/tests/unit/") .. "/examples"
local NAMES = {
  "hecate.test.Runner", "hecate.test.boot", "hecate.test.check_property", "hecate.test.run_parallel",
  "hecate.test.LineCoverage",
}

function T:test_every_example_runs_and_prints_what_it_says()
  examples.check(self, directory, NAMES)
end

return T
