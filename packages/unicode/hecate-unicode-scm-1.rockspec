rockspec_format = "3.0"
package = "hecate-unicode"
version = "scm-1"

source = {
  url = "git+https://github.com/hecate-framework/hecate-unicode.git",
}

description = {
  summary = "Unicode normalisation of UTF-8 strings: NFC, NFD, Hangul syllable arithmetic and canonical reordering.",
  homepage = "https://github.com/hecate-framework/hecate",
  license = "MIT",
}

dependencies = {
  "lua >= 5.5, < 5.6",
  "hecate-core",
  "hecate-unicode-data >= 18.0.0",
}

build = {
  type = "builtin",
  modules = {},
}
