rockspec_format = "3.0"
package = "hecate-json"
version = "scm-1"

source = {
  url = "git+https://github.com/hecate-framework/hecate-json.git",
}

description = {
  summary = "Fast, correct JSON codec (RFC 8259) with integer/float fidelity, explicit null and array markers, and precise error positions.",
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
