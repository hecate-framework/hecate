-- Third-party test data, downloaded by `lua tools/run.lua fetch-fixtures unicode` into
-- .hecate/fixtures/unicode/<name> (git-ignored). The sha256 pins the content (a version directory of unicode.org does
-- not change once published). The version must be the one of `hecate-unicode-data` (ADR 0032).
-- Unicode License v3; not vendored.
return {
  -- The conformance test of normalisation (UAX #15): every line of every part, NFC and NFD columns.
  { name = "NormalizationTest.txt", url = "https://www.unicode.org/Public/18.0.0/ucd/NormalizationTest.txt", sha256 = "25a50d816764b04abfb4a646d3eb2b2a803284c3873d9a06757b94fe4513dde3" },
}
