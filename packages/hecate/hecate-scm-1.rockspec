rockspec_format = "3.0"
package = "hecate"
version = "scm-1"

source = {
  url = "git+https://github.com/hecate-framework/hecate.git",
}

description = {
  summary = "Meta-rock `hecate`: depends on the standard edition and provides the `hecate` meta-module re-exporting the framework surface.",
  homepage = "https://github.com/hecate-framework/hecate",
  license = "MIT",
}

dependencies = {
  "lua >= 5.5, < 5.6",
  "hecate-core",
  "hecate-reactor",
  "hecate-net",
  "hecate-json",
  "hecate-log",
  "hecate-http",
  "hecate-schema",
  "hecate-router",
  "hecate-container",
  "hecate-config",
  "hecate-kernel",
  "hecate-openapi",
}

build = {
  type = "builtin",
  modules = {},
}
