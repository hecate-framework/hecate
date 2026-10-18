-- Site configuration of the public website, read by `hecate.doc` (ADR 0012). Data only:
-- the file is evaluated with an empty environment. Build with
--   lua packages/doc/bin/build.lua website --strict
-- (the output goes to website/dist, which is git-ignored).
return {
  title = "hecate", -- the name is never capitalised (brand kit)
  description = {
    en = "A modular, contract-first web API framework for Lua 5.5.",
    fr = "Un cadre applicatif modulaire, piloté par contrat, pour les API web en Lua 5.5.",
  },
  base = "/",
  url = "https://hecate.theandre.dev", -- provisional domain (OQ-10)
  default_locale = "en",
  locales = {
    { code = "en", label = "English" },
    { code = "fr", label = "Français" },
  },
  -- Sections of OUTLINE.md. A section without any page yet is left out of the navigation.
  nav = {
    { text = { en = "Tutorials", fr = "Tutoriels" }, link = "tutorials/" },
    { text = { en = "How-to guides", fr = "Guides pratiques" }, link = "how-to/" },
    { text = { en = "Reference", fr = "Référence" }, link = "reference/" },
    { text = { en = "Explanation", fr = "Explications" }, link = "explanation/" },
    { text = { en = "Community", fr = "Communauté" }, link = "community/" },
  },
  repository = "https://github.com/hecate-framework/hecate",
  edit_link = "https://github.com/hecate-framework/hecate/edit/main/website/{path}",
  exclude = { "README.md", "glossary-terms.md" }, -- the translators' notes are not pages
}
