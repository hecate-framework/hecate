rockspec_format = "3.0"
package = "hecate-kernel"
version = "scm-1"

source = {
  url = "git+https://github.com/hecate-framework/hecate-kernel.git",
}

description = {
  summary = "The application: feature modules, controllers, route modules, filters (chain of responsibility), problem details, lifecycle, workers and graceful shutdown.",
  homepage = "https://github.com/hecate-framework/hecate",
  license = "MIT",
}

dependencies = {
  "lua >= 5.5, < 5.6",
  "hecate-core",
  "hecate-reactor",
  "hecate-log",
  "hecate-http",
  "hecate-router",
  "hecate-schema",
  "hecate-container",
  "hecate-config",
  "hecate-json",
}

build = {
  type = "builtin",
  modules = {},
}
