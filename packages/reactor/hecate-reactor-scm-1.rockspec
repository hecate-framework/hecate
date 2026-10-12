rockspec_format = "3.0"
package = "hecate-reactor"
version = "scm-1"

source = {
  url = "git+https://github.com/hecate-framework/hecate-reactor.git",
}

description = {
  summary = "The reactor over libuv (luv): coroutine scheduler, futures, structured concurrency, synchronisation primitives, timers, signals, processes, file system and thread-pool offloading.",
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
