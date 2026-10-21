-- Third-party test data, downloaded by `lua tools/run.lua fetch-fixtures json` into
-- .hecate/fixtures/json/<name> (git-ignored). The commit hash pins the content.
return {
  -- https://github.com/nst/JSONTestSuite (MIT): `y_` files must decode, `n_` files must be rejected.
  { name = "JSONTestSuite", repository = "https://github.com/nst/JSONTestSuite", commit = "1ef36fa01286573e846ac449e8683f8833c5b26a", path = "test_parsing" },
}
