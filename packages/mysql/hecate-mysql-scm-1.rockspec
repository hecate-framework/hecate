rockspec_format = "3.0"
package = "hecate-mysql"
version = "scm-1"

source = {
  url = "git+https://github.com/hecate-framework/hecate-mysql.git",
}

description = {
  summary = "MySQL and MariaDB driver implementing the client/server protocol in Lua, with dialect detection.",
  homepage = "https://github.com/hecate-framework/hecate",
  license = "MIT",
}

dependencies = {
  "lua >= 5.5, < 5.6",
  "hecate-core",
  "hecate-reactor",
  "hecate-net",
  "hecate-sql",
}

build = {
  type = "builtin",
  modules = {},
}
