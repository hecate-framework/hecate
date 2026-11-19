rockspec_format = "3.0"
package = "hecate-doc"
version = "scm-1"

source = {
  url = "git+https://github.com/hecate-framework/hecate-doc.git",
}

description = {
  summary = "Documentation generator and static site builder with an MDN-like theme: guides in Markdown, code reference from LuaLS annotations, configuration reference, locales, search.",
  homepage = "https://github.com/hecate-framework/hecate",
  license = "MIT",
}

dependencies = {
  "lua >= 5.5, < 5.6",
  "hecate-core",
  "hecate-reactor",
  "hecate-json",
  "hecate-unicode",
}

build = {
  type = "builtin",
  modules = {},
}
