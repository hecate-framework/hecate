-- Interface strings of the theme, per locale. English is the source; a locale without a
-- string falls back to English. Sites override or add locales with `config.strings`.
-- The name of the project is never capitalised (brand kit), including in these strings.
global <const> pairs, ipairs, tostring, tonumber

local M = {}

---@type table<string, table<string, any>>
M.catalogue = {
  en = {
    skip_to_content = "Skip to content",
    main_navigation = "Main",
    sidebar_navigation = "Sidebar",
    home = "home",
    search = "Search",
    search_hint = "Type to search the documentation.",
    no_results = "No results for",
    results = "results",
    search_failed = "The search index could not be loaded.",
    search_navigate = "to navigate",
    search_select = "to open",
    search_close = "to close",
    close = "Close",
    language = "Language",
    switch_to_dark = "Switch to dark theme",
    switch_to_light = "Switch to light theme",
    toggle_menu = "Menu",
    sidebar_menu = "Menu",
    on_this_page = "On this page",
    previous_page = "Previous page",
    next_page = "Next page",
    pagination = "Previous and next page",
    edit_page = "Edit this page on GitHub",
    last_updated = "Last updated",
    repository = "GitHub repository",
    written_for = "Written for hecate %s and Lua %s",
    fallback_notice = "This page is not translated into this language yet. The English version is shown.",
    copy = "Copy",
    copy_code = "Copy code",
    copied = "Copied",
    copy_failed = "Copy failed",
    table = "Table",
    note = "Note",
    tip = "Tip",
    warning = "Warning",
    danger = "Danger",
    not_found_title = "Page not found",
    not_found_text = "The page you asked for does not exist, or it moved.",
    not_found_link = "Go to the home page",
    footer = "Released under the MIT licence.",
    date_format = "{day} {month} {year}",
    months = { "January", "February", "March", "April", "May", "June", "July", "August",
      "September", "October", "November", "December" },
  },
  fr = {
    skip_to_content = "Aller au contenu",
    main_navigation = "Principale",
    sidebar_navigation = "Menu latéral",
    home = "accueil",
    search = "Rechercher",
    search_hint = "Saisissez un terme pour chercher dans la documentation.",
    no_results = "Aucun résultat pour",
    results = "résultats",
    search_failed = "L’index de recherche n’a pas pu être chargé.",
    search_navigate = "pour naviguer",
    search_select = "pour ouvrir",
    search_close = "pour fermer",
    close = "Fermer",
    language = "Langue",
    switch_to_dark = "Passer au thème sombre",
    switch_to_light = "Passer au thème clair",
    toggle_menu = "Menu",
    sidebar_menu = "Menu",
    on_this_page = "Sur cette page",
    previous_page = "Page précédente",
    next_page = "Page suivante",
    pagination = "Page précédente et suivante",
    edit_page = "Modifier cette page sur GitHub",
    last_updated = "Dernière mise à jour",
    repository = "Dépôt GitHub",
    written_for = "Écrit pour hecate %s et Lua %s",
    fallback_notice = "Cette page n’est pas encore traduite dans cette langue. La version anglaise est affichée.",
    copy = "Copier",
    copy_code = "Copier le code",
    copied = "Copié",
    copy_failed = "Échec de la copie",
    table = "Tableau",
    note = "Note",
    tip = "Astuce",
    warning = "Attention",
    danger = "Danger",
    not_found_title = "Page introuvable",
    not_found_text = "La page demandée n’existe pas, ou elle a été déplacée.",
    not_found_link = "Retour à l’accueil",
    footer = "Publié sous licence MIT.",
    date_format = "{day} {month} {year}",
    months = { "janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août",
      "septembre", "octobre", "novembre", "décembre" },
  },
}

--- Returns the strings of a locale: English, then the built-in strings of the locale,
--- then the overrides from the site configuration.
---@param locale string
---@param overrides? table<string, table<string, any>>
---@return table<string, any>
function M.for_locale(locale, overrides)
  local merged = {}
  for _, source in ipairs({ M.catalogue.en, M.catalogue[locale] or {}, (overrides or {})[locale] or {} }) do
    for key, value in pairs(source) do merged[key] = value end
  end
  return merged
end

--- Formats an ISO 8601 date (`YYYY-MM-DD`, with an optional time) with the locale's month
--- names. Returns nil when the text is not a date.
---@param iso string
---@param strings table<string, any>
---@return string? text
---@return string? date  the `YYYY-MM-DD` part, for the `datetime` attribute
function M.format_date(iso, strings)
  local year, month, day = tostring(iso):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
  local month_number = month and tonumber(month)
  if not year or month_number < 1 or month_number > 12 then return nil end
  local text = strings.date_format:gsub("{(%w+)}", {
    day = tostring(tonumber(day)), month = strings.months[month_number], year = year,
  })
  return text, ("%s-%s-%s"):format(year, month, day)
end

return M
