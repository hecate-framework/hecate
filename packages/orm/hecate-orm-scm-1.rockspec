rockspec_format = "3.0"
package = "hecate-orm"
version = "scm-1"

source = {
  url = "git+https://github.com/hecate-framework/hecate-orm.git",
}

description = {
  summary = "Object-relational mapper: Data Mapper with Unit of Work, Identity Map, associations and repositories.",
  homepage = "https://github.com/hecate-framework/hecate",
  license = "MIT",
}

dependencies = {
  "lua >= 5.5, < 5.6",
  "hecate-core",
  "hecate-reactor",
  "hecate-sql",
  "hecate-query",
  "hecate-schema",
}

build = {
  type = "builtin",
  modules = {},
}
