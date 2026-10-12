rockspec_format = "3.0"
package = "hecate-sqlserver"
version = "scm-1"

source = {
  url = "git+https://github.com/hecate-framework/hecate-sqlserver.git",
}

description = {
  summary = "Microsoft SQL Server driver implementing TDS in Lua.",
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
