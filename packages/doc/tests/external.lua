-- Third-party test data, downloaded by `lua tools/run.lua fetch-fixtures doc` into
-- .hecate/fixtures/doc/<name> (git-ignored). The commit hash pins the content.
return {
  -- https://github.com/commonmark/commonmark-spec, tag 0.31.2 (CC BY-SA 4.0; not vendored): the
  -- examples of spec.txt run through the native module (OQ-37).
  { name = "commonmark-spec", repository = "https://github.com/commonmark/commonmark-spec", commit = "9103e341a973013013bb1a80e13567007c5cef6f", path = "spec.txt" },
  -- https://github.com/github/cmark-gfm, tag 0.29.0.gfm.13 (BSD-2-Clause and MIT; not vendored): the
  -- examples of the GFM specification tagged with an extension.
  { name = "cmark-gfm", repository = "https://github.com/github/cmark-gfm", commit = "587a12bb54d95ac37241377e6ddc93ea0e45439b", path = "test/spec.txt" },
}
