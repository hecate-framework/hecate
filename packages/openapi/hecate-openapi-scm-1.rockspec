rockspec_format = "3.0"
package = "hecate-openapi"
version = "scm-1"

source = {
  url = "git+https://github.com/hecate-framework/hecate-openapi.git",
}

description = {
  summary = "OpenAPI 3.1 document assembly from the route table, schemas and project settings; served endpoint, export, lint and breaking-change diff.",
  homepage = "https://github.com/hecate-framework/hecate",
  license = "MIT",
}

dependencies = {
  "lua >= 5.5, < 5.6",
  "hecate-core",
  "hecate-schema",
  "hecate-router",
  "hecate-json",
}

build = {
  type = "builtin",
  modules = {},
}
