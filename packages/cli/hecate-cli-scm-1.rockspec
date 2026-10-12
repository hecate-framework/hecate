rockspec_format = "3.0"
package = "hecate-cli"
version = "scm-1"

source = {
  url = "git+https://github.com/hecate-framework/hecate-cli.git",
}

description = {
  summary = "The `hecate` command: toolchains, projects, dependencies (LuaRocks), development server, tests, contracts, documentation, migrations, scaffolding, packaging.",
  homepage = "https://github.com/hecate-framework/hecate",
  license = "MIT",
}

dependencies = {
  "lua >= 5.5, < 5.6",
  "hecate-core",
  "hecate-reactor",
  "hecate-log",
  "hecate-json",
  "hecate-schema",
  "hecate-kernel",
  "hecate-test",
  "hecate-doc",
  "hecate-openapi",
  "hecate-migration",
}

build = {
  type = "builtin",
  modules = {},
}
