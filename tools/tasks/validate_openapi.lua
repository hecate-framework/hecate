-- validate-openapi: validates the OpenAPI documents of the tests (`.hecate/openapi-validate/*.json`, written by
-- `lua tools/run.lua test openapi`) and the golden file against the pinned official OpenAPI 3.1 JSON Schema
-- (`fetch-fixtures openapi`) with Python `jsonschema` (ADR 0031). Development-only: skips locally when the documents, the
-- schema or the Python environment are absent, fails when CI is `true`.
local openapi_validate = require("lib.openapi_validate")

return {
  description = "validate the OpenAPI documents of the tests against the official OpenAPI 3.1 JSON Schema (Python jsonschema; skips locally when absent, fails in CI)",
  run = function(ctx)
    return openapi_validate.run({ root = ctx.root, ci = ctx.ci, getenv = ctx.getenv })
  end,
}
