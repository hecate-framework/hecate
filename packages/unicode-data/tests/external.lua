-- Third-party data, downloaded by `lua tools/run.lua fetch-fixtures unicode-data` into
-- .hecate/fixtures/unicode-data/<name> (git-ignored). The sha256 pins the content: the files of a version directory of
-- unicode.org do not change once published. These are the inputs of `gen-unicode` (ADR 0032); the Unicode version is the
-- one in the URL, and every URL must name the same version. Updating is a human step: change the three values
-- here and in the `unicode` package, run `lua tools/run.lua fetch-fixtures unicode-data`, `gen-unicode` and the tests.
-- Unicode License v3 (not vendored here; the generated tables carry the notice).
return {
  { name = "UnicodeData.txt", url = "https://www.unicode.org/Public/18.0.0/ucd/UnicodeData.txt", sha256 = "0736451de439ae7baf1425136617da495e09ee5afbe6e394374db7009ea08950" },
  { name = "DerivedNormalizationProps.txt", url = "https://www.unicode.org/Public/18.0.0/ucd/DerivedNormalizationProps.txt", sha256 = "98ac7f67d985fe781e317f6182e885e94cabb0c314769e6dd73e48b226931ccd" },
}
