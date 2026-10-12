rockspec_format = "3.0"
package = "hecate-router"
version = "scm-1"

source = {
  url = "git+https://github.com/hecate-framework/hecate-router.git",
}

description = {
  summary = "Radix-tree router over URI templates (RFC 6570 level-1 subset) with 404/405 handling and reverse routing.",
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
