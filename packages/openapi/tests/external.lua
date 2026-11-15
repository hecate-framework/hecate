-- Third-party test data, downloaded by `lua tools/run.lua fetch-fixtures openapi` into
-- .hecate/fixtures/openapi/<name> (git-ignored). The commit hash pins the content.
return {
  -- https://github.com/OAI/spec.openapis.org (Apache-2.0), head of `main` on 2026-11-12: the publication site of the
  -- OpenAPI Initiative. The official JSON Schema of OpenAPI 3.1 documents is its file `oas/3.1/schema/2026-11-05`
  -- (the former `schemas/v3.1/schema.json` of OAI/OpenAPI-Specification is no longer in that repository: the sources
  -- are YAML, the published JSON lives here), read by `conformance_test.lua`.
  { name = "spec.openapis.org", repository = "https://github.com/OAI/spec.openapis.org", commit = "ce49002c7bbd323819555464eb479523923f6754", path = "oas/3.1/schema" },
}
