-- Site configuration of the documentation of the hello example, read by
-- `hecate.doc` (data only). Built by `lua examples/hello/build_docs.lua`.
-- It shows the theme extension points: a logo, and a CSS file with its own
-- palette (light and dark), fonts, radii and sidebar width.
return {
  title = "hello",
  description = "A small JSON API on hecate: validated input, problem details, workers.",
  base = "/",
  logo = { light = "logo.svg", dark = "logo-dark.svg" },
  theme = "hello-theme.css",
  llms = true, -- also writes llms.txt and llms-full.txt
}
