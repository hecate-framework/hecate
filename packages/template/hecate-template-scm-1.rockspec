rockspec_format = "3.0"
package = "hecate-template"
version = "scm-1"

source = {
  url = "git+https://github.com/hecate-framework/hecate-template.git",
}

description = {
  summary = "Compiled templates with contextual auto-escaping, for HTML and text responses.",
  homepage = "https://github.com/hecate-framework/hecate",
  license = "MIT",
}

dependencies = {
  "lua >= 5.5, < 5.6",
  "hecate-core",
  "hecate-kernel",
}

build = {
  type = "builtin",
  modules = {},
}
