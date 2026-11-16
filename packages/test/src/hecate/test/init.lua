-- hecate.test: xUnit test framework running inside the reactor (ADR 0008, testing.md).
global <const> require

local case_module = require("hecate.test.case")
local assertions = require("hecate.test.assertions")
local failure = require("hecate.test.failure")
local discovery = require("hecate.test.discovery")
local generate = require("hecate.test.generate")

--- The test framework: cases and assertions, the runner and its reporters, discovery and command-line selection,
--- the in-process client and fixtures, generators and properties, and coverage.
---@class hecate.test
---@field AssertionFailure hecate.test.AssertionFailure  raised by a failed assertion
---@field LoadError hecate.test.LoadError  raised when a test file cannot be loaded
---@field Runner hecate.test.Runner  executes cases, each test in its own reactor scope
---@field ConsoleReporter hecate.test.ConsoleReporter  one line per suite with a loading bar, for people
---@field TapReporter hecate.test.TapReporter  TAP 14 reporter
---@field JUnitReporter hecate.test.JUnitReporter  JUnit XML reporter, for continuous-integration servers
---@field JsonLinesReporter hecate.test.JsonLinesReporter  event stream, one JSON object per line, for IDE adapters
---@field Client hecate.test.Client  in-process HTTP client: serves requests to an application's action without a socket
---@field RouteCoverage hecate.test.RouteCoverage  the routes of an application that the requests of a test reached (the third result of `boot`)
---@field LineCoverage hecate.test.LineCoverage  records and reports the lines of the sources that ran (LCOV)
---@field Generator hecate.test.Generator  a seeded source of values valid for a schema
---@field Case fun(name: string): hecate.test.Case  declares a test case: a class whose `test_*` methods are tests
---@field is_case fun(value: any): boolean  whether `value` is a test case
---@field of_type fun(name: string): fun(value: any): boolean  a shape predicate: true for a value of that Lua type
---@field discover fun(directory: string): string[]  the `*_test.lua` files under a directory (async; raises for an unreadable directory)
---@field load fun(path: string): hecate.test.Case  loads the case a test file returns
---@field parse_arguments fun(args: string[]): hecate.test.ParsedArguments  command-line arguments to runner options and paths
---@field run_parallel fun(paths: string[], options?: hecate.test.ParallelOptions): hecate.test.Summary  runs files in worker processes (async)
---@field boot fun(options?: hecate.kernel.ApplicationOptions, overrides?: hecate.test.Override[]): hecate.test.Client, hecate.kernel.Application, hecate.test.RouteCoverage  boots an application for a test
---@field check_property fun(schema: hecate.schema.Schema, property: (fun(value: any): boolean?), options?: hecate.test.PropertyOptions): hecate.test.PropertyResult  runs a property over generated values and shrinks a counterexample
---@field generate fun(schema: hecate.schema.Schema, seed?: integer): any  one value valid for the schema (seed default 1)
---@field generate_invalid fun(schema: hecate.schema.Schema, seed?: integer): any, { path: string, code: string }  a valid value broken in one place, and the violation (seed default 1)
local test = {
  AssertionFailure = failure.AssertionFailure,
  LoadError = discovery.LoadError,
  Runner = require("hecate.test.runner"),
  ConsoleReporter = require("hecate.test.reporters.console"),
  TapReporter = require("hecate.test.reporters.tap"),
  JUnitReporter = require("hecate.test.reporters.junit"),
  JsonLinesReporter = require("hecate.test.reporters.json_lines"),
  Client = require("hecate.test.client"),
  RouteCoverage = require("hecate.test.coverage"),
  LineCoverage = require("hecate.test.line_coverage"),
  Generator = generate.Generator,
  Case = case_module.Case,
  is_case = case_module.is_case,
  of_type = assertions.of_type,
  discover = discovery.discover,
  load = discovery.load,
  parse_arguments = require("hecate.test.selection").parse,
  run_parallel = require("hecate.test.parallel").run,
  boot = require("hecate.test.fixture").boot,
  check_property = require("hecate.test.property").check_property,
  generate = generate.generate,
  generate_invalid = generate.generate_invalid,
}

return test
