rockspec_format = "3.0"
package = "hecate-postgresql"
version = "scm-1"

source = {
  url = "git+https://github.com/hecate-framework/hecate-postgresql.git",
}

description = {
  summary = "PostgreSQL driver implementing the frontend/backend protocol v3 in Lua.",
  homepage = "https://github.com/hecate-framework/hecate",
  license = "MIT",
}

dependencies = {
  "lua >= 5.5, < 5.6",
  "hecate-core",
  "hecate-reactor",
  "hecate-net",
  "hecate-sql",
}

build = {
  type = "builtin",
  modules = {},
}
