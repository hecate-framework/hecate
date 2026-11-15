-- hecate.test: xUnit test framework running inside the reactor (ADR 0008, testing.md).
global <const> require

local case_module = require("hecate.test.case")
local assertions = require("hecate.test.assertions")
local failure = require("hecate.test.failure")
local discovery = require("hecate.test.discovery")

--- The test framework: cases, assertions, runner, discovery and reporters.
---@class hecate.test
---@field AssertionFailure hecate.test.AssertionFailure  raised by a failed assertion
---@field LoadError hecate.test.LoadError  raised when a test file cannot be loaded
---@field Runner hecate.test.Runner  executes cases, each test in its own reactor scope
---@field ConsoleReporter hecate.test.ConsoleReporter  one line per suite with a loading bar, for people
---@field TapReporter hecate.test.TapReporter  TAP 14 reporter
---@field Client hecate.test.Client  in-process HTTP client: serves requests to an application's action without a socket
---@field JUnitReporter hecate.test.JUnitReporter  JUnit XML reporter, for continuous-integration servers
---@field JsonLinesReporter hecate.test.JsonLinesReporter  event stream, one JSON object per line, for IDE adapters
local test = {
  AssertionFailure = failure.AssertionFailure,
  LoadError = discovery.LoadError,
  Runner = require("hecate.test.runner"),
  ConsoleReporter = require("hecate.test.reporters.console"),
  TapReporter = require("hecate.test.reporters.tap"),
  Client = require("hecate.test.client"),
  JUnitReporter = require("hecate.test.reporters.junit"),
  JsonLinesReporter = require("hecate.test.reporters.json_lines"),
}

test.Case = case_module.Case
test.is_case = case_module.is_case
test.of_type = assertions.of_type
test.discover = discovery.discover
test.load = discovery.load
test.boot = require("hecate.test.fixture").boot
test.parse_arguments = require("hecate.test.selection").parse

return test
