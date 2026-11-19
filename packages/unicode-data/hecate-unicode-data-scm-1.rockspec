rockspec_format = "3.0"
package = "hecate-unicode-data"
version = "scm-1"

source = {
  url = "git+https://github.com/hecate-framework/hecate-unicode-data.git",
}

description = {
  summary = "Generated Unicode Character Database tables (combining classes, canonical decompositions and compositions), versioned by the Unicode version.",
  homepage = "https://github.com/hecate-framework/hecate",
  license = "Unicode-3.0",
}

dependencies = {
  "lua >= 5.5, < 5.6",
}

build = {
  type = "builtin",
  modules = {},
}
