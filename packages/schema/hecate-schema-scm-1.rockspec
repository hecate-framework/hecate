rockspec_format = "3.0"
package = "hecate-schema"
version = "scm-1"

source = {
  url = "git+https://github.com/hecate-framework/hecate-schema.git",
}

description = {
  summary = "Refinement types, composition, coercion and validation with JSON Pointer error paths; emits JSON Schema 2020-12.",
  homepage = "https://github.com/hecate-framework/hecate",
  license = "MIT",
}

dependencies = {
  "lua >= 5.5, < 5.6",
  "hecate-core",
  "hecate-json",
}

build = {
  type = "builtin",
  modules = {},
}
