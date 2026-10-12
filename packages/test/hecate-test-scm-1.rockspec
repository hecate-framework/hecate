rockspec_format = "3.0"
package = "hecate-test"
version = "scm-1"

source = {
  url = "git+https://github.com/hecate-framework/hecate-test.git",
}

description = {
  summary = "xUnit test framework running inside the reactor: cases, suites, fixtures, assertions, in-process HTTP client, contract conformance, property-based testing, coverage.",
  homepage = "https://github.com/hecate-framework/hecate",
  license = "MIT",
}

dependencies = {
  "lua >= 5.5, < 5.6",
  "hecate-core",
  "hecate-reactor",
  "hecate-log",
  "hecate-schema",
  "hecate-kernel",
  "hecate-openapi",
  "hecate-json",
}

build = {
  type = "builtin",
  modules = {},
}
