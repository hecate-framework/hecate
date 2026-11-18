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
  sidebar_marker = true, -- the accent bar of the current page in the sidebar is opt-in; the website keeps it
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
  source_edit_link = "https://github.com/hecate-framework/hecate/edit/main/{path}", -- generated reference pages
  -- The website of the framework publishes both audiences (OQ-144), as ONE combined site until its restructure
  -- (option (a) of OQ-144): by default several audiences are written as separate sites, one per audience.
  audiences = { "user", "maintainer" },
  default_audience = "user", -- no page of website/ is labelled yet: every page stays what it was, a user page
  audience_sites = "merged",
  llms = true, -- writes llms.txt and llms-full.txt (default locale, published pages)
  exclude = { "README.md", "glossary-terms.md" }, -- the translators' notes are not pages
}
