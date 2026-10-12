rockspec_format = "3.0"
package = "hecate-sql"
version = "scm-1"

source = {
  url = "git+https://github.com/hecate-framework/hecate-sql.git",
}

description = {
  summary = "Driver-agnostic SQL interfaces: drivers, connections, prepared statements, transactions and savepoints, connection pool, type mapping, instrumentation.",
  homepage = "https://github.com/hecate-framework/hecate",
  license = "MIT",
}

dependencies = {
  "lua >= 5.5, < 5.6",
  "hecate-core",
  "hecate-reactor",
  "hecate-net",
  "hecate-log",
}

build = {
  type = "builtin",
  modules = {},
}
