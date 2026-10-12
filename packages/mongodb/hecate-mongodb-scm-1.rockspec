rockspec_format = "3.0"
package = "hecate-mongodb"
version = "scm-1"

source = {
  url = "git+https://github.com/hecate-framework/hecate-mongodb.git",
}

description = {
  summary = "MongoDB driver (OP_MSG + BSON) and document mapper sharing the unit-of-work vocabulary.",
  homepage = "https://github.com/hecate-framework/hecate",
  license = "MIT",
}

dependencies = {
  "lua >= 5.5, < 5.6",
  "hecate-core",
  "hecate-reactor",
  "hecate-net",
}

build = {
  type = "builtin",
  modules = {},
}
