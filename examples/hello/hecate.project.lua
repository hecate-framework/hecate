-- `examples/hello` is a Hecate project: `hecate serve` runs it,
-- `hecate test` tests it, `hecate contract lint` checks its contract
-- and `hecate doc build` builds its documentation (see README.md).
return {
  name = "hello",
  version = "0.1.0",
  description = "A small JSON API on Hecate: validated input, problem details, workers.",
  lua = "5.5",
  dependencies = {
    hecate = "~> 0.0",
  },
  contract = { title = "hello", version = "0.1.0" },
  doc = {
    guides_dir = "docs",
    output_dir = "docs/dist",
    sources_dir = "src",
    package_name = "hello",
  },
}
