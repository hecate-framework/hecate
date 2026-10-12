rockspec_format = "3.0"
package = "hecate-migration"
version = "scm-1"

source = {
  url = "git+https://github.com/hecate-framework/hecate-migration.git",
}

description = {
  summary = "Versioned, reversible schema migrations with checksums and CLI integration.",
  homepage = "https://github.com/hecate-framework/hecate",
  license = "MIT",
}

dependencies = {
  "lua >= 5.5, < 5.6",
  "hecate-core",
  "hecate-sql",
  "hecate-query",
  "hecate-log",
}

build = {
  type = "builtin",
  modules = {},
}
