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
  modules = {
    ["hecate.core"] = "src/hecate/core/init.lua",
    ["hecate.core.class"] = "src/hecate/core/class.lua",
    ["hecate.core.trait"] = "src/hecate/core/trait.lua",
    ["hecate.core.interface"] = "src/hecate/core/interface.lua",
    ["hecate.core.introspection"] = "src/hecate/core/introspection.lua",
    ["hecate.core.error"] = "src/hecate/core/error.lua",
    ["hecate.core.compat"] = "src/hecate/core/compat.lua",
    ["hecate.core.internal.registry"] = "src/hecate/core/internal/registry.lua",
    ["hecate.core.internal.raise"] = "src/hecate/core/internal/raise.lua",
  },
}
