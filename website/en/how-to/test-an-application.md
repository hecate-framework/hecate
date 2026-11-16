---
description: Test an application with hecate.test, write test cases, boot the application with fakes, send requests without a socket, see which routes a test never reached, and check properties over generated values.
hecate: "0.x"
lua: "5.5"
order: 21
---

# Test an application

This guide shows how to test an application with `hecate.test`. It is written for hecate 0.x and Lua 5.5, and the
package is **alpha**: the parts listed at the end are not available yet.

`hecate.test` runs each test in a reactor of its own, so a test can suspend, fork and wait like production code. A
test that leaves coroutines running fails, and they are cancelled, so one test never disturbs the next.

## Write a test case

A test case is a class created with `test.Case`. Each method whose name starts with `test_` is a test. The hooks
`set_up` and `tear_down` run around each test, `set_up_case` and `tear_down_case` around the whole case. Assertions
are methods of the case: `assert_equal` compares tables structurally and lists each difference by path, and
`assert_error` checks the class and the code of a raised error.

```lua
local test = require("hecate.test")
local T = test.Case("GreetingTest")

function T:test_greeting_is_polite()
  self:assert_match("^Hello", "Hello, Ada")
end

return require("hecate.core").finalise(T)
```

A test file ends with the finalised case. `test.discover(directory)` finds the `*_test.lua` files under a directory,
`test.load(path)` loads one, and `test.Runner` runs the cases and sends events to a reporter: the console reporter
draws one line per suite, and `TapReporter`, `JUnitReporter` and `JsonLinesReporter` write the formats their names
give. A run summary carries `exit_code`, 0 when every test passed.

Tests can be targeted. The runner options `filter` (a Lua pattern on the full test name), `cases` (case names), `tags`
and `exclude_tags` select tests, and `test.parse_arguments(args)` turns the arguments of a command line
(`--filter`, `--case`, `--tag`, `--exclude-tag` and paths) into those options. A case declares tags with `tags`, and a
single test with `test_tags`.

## Boot the application

`test.boot(options, overrides)` boots a `hecate.kernel` application and returns a client, the application and a route
coverage. The `options` are those of `kernel.Application`. Each override replaces a service **after** every module has
bound its own, so a fake takes the place of the real service whoever bound it. An override is `{ key, value }` for an
existing object, or `{ key, definition, options }` for a class or a factory. A key that is not bound raises
`hecate.container.MissingBindingError`.

The client sends requests to the application without a socket, through the code path of the server. `get`, `post`,
`put`, `patch`, `delete`, `head` and `request` return the response and, when the action raised, the failure the server
would have logged. The `json` option encodes a value and sets the content type.

<!-- example: packages/test/examples/hecate.test.boot.lua -->
```lua
-- Boot an application for a test: replace a service by a fake, send requests
-- without a socket, and see which routes the test never reached.
local reactor = require("hecate.reactor")
local kernel = require("hecate.kernel")
local test = require("hecate.test")

local routes = kernel.routes("greetings")
routes:get("/greeting", {
  name = "show_greeting",
  action = function(request)
    return { text = request.services:resolve("greeter") }
  end,
})
routes:delete("/greeting", {
  name = "delete_greeting",
  action = function() return { deleted = true } end,
})

local options = {
  routes = { routes },
  modules = { {
    name = "greetings",
    services = function(c)
      c:bind("greeter", function() return "hello" end,
        { lifetime = "singleton" })
    end,
  } },
}

reactor.run(function()
  -- The override is applied after every module has bound its services.
  local client, _, coverage = test.boot(options, {
    { key = "greeter", value = "fake" },
  })
  local response = client:get("/greeting")
  print(response.status, response:read_content())
  -- Prints: 200	{"text":"fake"}
  print(client:get("/nowhere").status)
  -- Prints: 404
  print(coverage:report())
  -- Prints: 1 of 2 routes exercised
  -- not exercised: delete_greeting
end)
```

Responses are validated against the schemas the routes declare, so a response that breaks the contract answers `500`
in the test. Pass `validate_responses = false` in the options to turn it off. The coverage lists the named routes
that served a request, `exercised()` and `missed()`, and `report()` prints both. A `404`, a `405` and an automatic
`OPTIONS` answer exercise no route.

## Check properties

An example-based test checks the values you thought of. A property is checked over values generated from a schema, so
it covers the ones you did not. `test.generate(schema, seed)` returns one valid value, and `test.Generator` gives a
reproducible sequence with `next()`. The same seed gives the same values on every platform. `check_property` runs a
property, which fails by returning `false` or by raising, and shrinks the first counterexample: integers move toward
zero, strings and arrays get shorter, objects lose properties, and a candidate is kept only if the schema still accepts
it. `Case:assert_property` does the same inside a test and names the seed and the counterexample in the failure.

<!-- example: packages/test/examples/hecate.test.check_property.lua -->
```lua
-- Check a property over values generated from a schema. A failing property
-- is shrunk to a small counterexample that still conforms to the schema.
local schema = require("hecate.schema")
local test = require("hecate.test")

local age = schema.integer({ minimum = 0, maximum = 120 })

-- A property fails by returning false (or by raising).
local ok = test.check_property(age, function(n) return n >= 0 end)
print(ok.ok, ok.runs)
-- Prints: true	100

-- The seed makes the run reproducible; the counterexample is the smallest
-- failing value the shrinking reached.
local result = test.check_property(age, function(n) return n < 18 end,
  { seed = 7 })
print(result.ok, result.counterexample)
-- Prints: false	18

-- Values that break the schema in exactly one place, with the violation.
local value, expected = test.generate_invalid(age, 1)
print(age:validate(value), expected.code)
-- Prints: false	maximum
```

`generate_invalid` is the other direction. It breaks a valid value in exactly one place and returns the violation that
validation reports, with its JSON Pointer `path` and its `code`, which makes it the way to test that a route refuses
what it must refuse.

## Run files in parallel

`test.run_parallel(paths, options)` runs each test file in a worker process of its own, with its own reactor, and
returns the same summary as `Runner:run`. It suspends, so call it inside `reactor.run`. The option `jobs` is the
number of workers running at once (default 2), `runner` holds the runner options each worker gets (`filter`, `cases`,
`tags`, `exclude_tags`, `clock`), and `reporter` receives the events in the order of the paths, so the stream has the
shape of a sequential run.

```lua
local reactor = require("hecate.reactor")
local test = require("hecate.test")

reactor.run(function()
  local paths = test.discover("tests")
  local summary = test.run_parallel(paths, { jobs = 4 })
  print(summary.exit_code)
end)
```

Two limits of this first version: the reporter sees nothing until every worker has finished, because the plan of a run
needs the total of all files, and what a test prints to its standard output is dropped. Tests that use a fixed port or
a shared database should not run in parallel until the rule for them is written.

## Limits

- A schema with a `pattern` cannot be generated, and raises `ArgumentError`.
- Integers shrink toward zero, one step at a time near a far bound.
- Not available yet: database fixtures with a transaction rolled back per test, and line coverage output (LCOV)
  from `hecate.test` itself (the `coverage` task of the repository measures the packages meanwhile).
