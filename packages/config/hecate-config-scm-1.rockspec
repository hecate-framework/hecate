rockspec_format = "3.0"
package = "hecate-config"
version = "scm-1"

source = {
  url = "git+https://github.com/hecate-framework/hecate-config.git",
}

description = {
  summary = "Layered configuration (defaults, environment files, environment variables, secrets) validated by schemas at boot.",
  homepage = "https://github.com/hecate-framework/hecate",
  license = "MIT",
}

dependencies = {
  "lua >= 5.5, < 5.6",
  "hecate-core",
  "hecate-schema",
}

build = {
  type = "builtin",
  modules = {},
}
