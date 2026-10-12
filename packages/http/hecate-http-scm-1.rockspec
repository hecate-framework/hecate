rockspec_format = "3.0"
package = "hecate-http"
version = "scm-1"

source = {
  url = "git+https://github.com/hecate-framework/hecate-http.git",
}

description = {
  summary = "HTTP/1.1 server and client with a message model following RFC 9110 semantics.",
  homepage = "https://github.com/hecate-framework/hecate",
  license = "MIT",
}

dependencies = {
  "lua >= 5.5, < 5.6",
  "hecate-core",
  "hecate-reactor",
  "hecate-net",
  "hecate-json",
  "hecate-log",
}

build = {
  type = "builtin",
  modules = {},
}
