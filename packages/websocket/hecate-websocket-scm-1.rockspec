rockspec_format = "3.0"
package = "hecate-websocket"
version = "scm-1"

source = {
  url = "git+https://github.com/hecate-framework/hecate-websocket.git",
}

description = {
  summary = "WebSocket protocol (RFC 6455) server and client integrated with the kernel.",
  homepage = "https://github.com/hecate-framework/hecate",
  license = "MIT",
}

dependencies = {
  "lua >= 5.5, < 5.6",
  "hecate-core",
  "hecate-reactor",
  "hecate-net",
  "hecate-http",
}

build = {
  type = "builtin",
  modules = {},
}
