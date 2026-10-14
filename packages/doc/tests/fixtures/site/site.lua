-- Site configuration of the test fixture: data only, evaluated with an empty environment.
return {
  title = "hecate",
  description = {
    en = "Contract-first web APIs for Lua 5.5.",
    fr = "API web pilotées par contrat pour Lua 5.5.",
  },
  base = "/",
  url = "https://docs.example.test",
  default_locale = "en",
  locales = {
    { code = "en", label = "English" },
    { code = "fr", label = "Français" },
  },
  nav = {
    { text = { en = "Guide", fr = "Guide" }, link = "guide/" },
    { text = { en = "Reference", fr = "Référence" }, link = "reference/" },
    { text = "Repository", link = "https://github.com/hecate-framework/hecate" },
  },
  repository = "https://github.com/hecate-framework/hecate",
  edit_link = "https://github.com/hecate-framework/hecate/edit/main/packages/doc/tests/fixtures/site/{path}",
  footer = { en = "Fixture site for hecate.doc tests. MIT licence.", fr = "Site de test de hecate.doc. Licence MIT." },
}
