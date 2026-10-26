rockspec_format = "3.0"
package = "hecate-core"
version = "scm-1"

source = {
  url = "git+https://github.com/hecate-framework/hecate-core.git",
}

description = {
  summary = "Object model (classes, traits, interfaces), error hierarchy, enumerations, value objects and Lua-version compatibility shims.",
  homepage = "https://github.com/hecate-framework/hecate",
  license = "MIT",
}

dependencies = {
  "lua >= 5.5, < 5.6",
}

build = {
  type = "builtin",
  modules = {},
}
