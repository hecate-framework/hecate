rockspec_format = "3.0"
package = "hecate-security"
version = "scm-1"

source = {
  url = "git+https://github.com/hecate-framework/hecate-security.git",
}

description = {
  summary = "Authentication (bearer tokens, JWT, sessions), authorisation policies, password hashing.",
  homepage = "https://github.com/hecate-framework/hecate",
  license = "MIT",
}

dependencies = {
  "lua >= 5.5, < 5.6",
  "hecate-core",
  "hecate-kernel",
  "hecate-schema",
  "hecate-json",
}

build = {
  type = "builtin",
  modules = {},
}
