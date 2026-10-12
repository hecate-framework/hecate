rockspec_format = "3.0"
package = "hecate-net"
version = "scm-1"

source = {
  url = "git+https://github.com/hecate-framework/hecate-net.git",
}

description = {
  summary = "TCP/UDP streams, DNS resolution, buffered readers/writers and TLS, all suspending transparently.",
  homepage = "https://github.com/hecate-framework/hecate",
  license = "MIT",
}

dependencies = {
  "lua >= 5.5, < 5.6",
  "hecate-core",
  "hecate-reactor",
}

build = {
  type = "builtin",
  modules = {},
}
