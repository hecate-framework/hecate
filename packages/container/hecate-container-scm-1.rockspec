rockspec_format = "3.0"
package = "hecate-container"
version = "scm-1"

source = {
  url = "git+https://github.com/hecate-framework/hecate-container.git",
}

description = {
  summary = "Inversion-of-control container: bindings, lifetimes (singleton, scoped, transient), constructor injection, cycle detection at boot.",
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
