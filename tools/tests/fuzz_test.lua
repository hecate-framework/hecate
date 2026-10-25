local test = require("harness.test")
local fuzz = require("lib.fuzz")
local T = test.Case("FuzzTest")

function T:test_parse_reads_target_and_seconds()
  local options = assert(fuzz.parse({ "feed", "--seconds", "30" }))
  self:assert_equal("feed", options.target)
  self:assert_equal(30, options.seconds)
end

function T:test_parse_defaults_to_sixty_seconds()
  self:assert_equal(60, assert(fuzz.parse({ "feed" })).seconds)
end

function T:test_parse_rejects_a_missing_target_and_a_bad_duration()
  self:assert_nil(fuzz.parse({}))
  self:assert_nil(fuzz.parse({ "feed", "--seconds", "x" }))
  self:assert_nil(fuzz.parse({ "feed", "--seconds" }))
end

function T:test_find_locates_the_crate_of_a_target()
  local targets = { { package = "net", name = "feed" }, { package = "net", name = "private_key" } }
  self:assert_equal("net", fuzz.find(targets, "private_key").package)
  self:assert_nil(fuzz.find(targets, "missing"))
end

function T:test_command_runs_cargo_fuzz_with_a_time_limit()
  local cmd = fuzz.command("packages/net/native", "feed", 45)
  self:assert_true(cmd:find("cargo +nightly fuzz run feed", 1, true) ~= nil)
  self:assert_true(cmd:find("-max_total_time=45", 1, true) ~= nil)
end

return T
