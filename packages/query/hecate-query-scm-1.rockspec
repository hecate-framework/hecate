rockspec_format = "3.0"
package = "hecate-query"
version = "scm-1"

source = {
  url = "git+https://github.com/hecate-framework/hecate-query.git",
}

description = {
  summary = "Query builder using relational-algebra vocabulary (projection, selection, join, rename, union) rendered per SQL dialect.",
  homepage = "https://github.com/hecate-framework/hecate",
  license = "MIT",
}

dependencies = {
  "lua >= 5.5, < 5.6",
  "hecate-core",
}

build = {
  type = "builtin",
  modules = {},
}
