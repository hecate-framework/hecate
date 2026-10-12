rockspec_format = "3.0"
package = "hecate-log"
version = "scm-1"

source = {
  url = "git+https://github.com/hecate-framework/hecate-log.git",
}

description = {
  summary = "Structured logging with RFC 5424 severities, per-scope context and pluggable sinks.",
  homepage = "https://github.com/hecate-framework/hecate",
  license = "MIT",
}

dependencies = {
  "lua >= 5.5, < 5.6",
  "hecate-core",
  "hecate-reactor",
  "hecate-json",
}

build = {
  type = "builtin",
  modules = {},
}
