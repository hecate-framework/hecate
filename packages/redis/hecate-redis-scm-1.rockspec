rockspec_format = "3.0"
package = "hecate-redis"
version = "scm-1"

source = {
  url = "git+https://github.com/hecate-framework/hecate-redis.git",
}

description = {
  summary = "Redis client (RESP3 with RESP2 fallback), compatible with Valkey and KeyDB.",
  homepage = "https://github.com/hecate-framework/hecate",
  license = "MIT",
}

dependencies = {
  "lua >= 5.5, < 5.6",
  "hecate-core",
  "hecate-reactor",
  "hecate-net",
}

build = {
  type = "builtin",
  modules = {},
}
