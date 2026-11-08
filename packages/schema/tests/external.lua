-- Third-party test data, downloaded by `lua tools/run.lua fetch-fixtures schema` into
-- .hecate/fixtures/schema/<name> (git-ignored). The commit hash pins the content.
return {
  -- https://github.com/json-schema-org/JSON-Schema-Test-Suite (MIT), head of `main` on 2026-11-08: the official cases
  -- of the 2020-12 dialect (`tests/draft2020-12/*.json`), read by `json_schema_suite_test.lua`.
  { name = "JSON-Schema-Test-Suite", repository = "https://github.com/json-schema-org/JSON-Schema-Test-Suite", commit = "245a45abc90190c0bff04d97e6d2b541b4bb9f12", path = "tests/draft2020-12" },
}
