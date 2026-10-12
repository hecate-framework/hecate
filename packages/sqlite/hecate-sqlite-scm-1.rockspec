rockspec_format = "3.0"
package = "hecate-sqlite"
version = "scm-1"

source = {
  url = "git+https://github.com/hecate-framework/hecate-sqlite.git",
}

description = {
  summary = "SQLite driver: C binding to the vendored amalgamation, executed on the libuv thread pool.",
  homepage = "https://github.com/hecate-framework/hecate",
  license = "MIT",
}

dependencies = {
  "lua >= 5.5, < 5.6",
  "hecate-core",
  "hecate-reactor",
  "hecate-sql",
}

build = {
  type = "builtin",
  modules = {},
}
