-- HTML templates of the theme: the page layout (header with logo, section links, search,
-- locale switch, theme toggle and repository link; sidebar; page; "On this page" outline;
-- previous/next cards; footer) and the not-found page. Every dynamic value goes through
-- `html.escape` or `html.attributes`; the page body is the only trusted HTML, and it comes
-- from the Markdown renderer, which escapes by default.
-- Accessibility (WCAG 2.2 AA): skip link first, landmarks with names, `aria-current`,
-- disclosure buttons with `aria-expanded`, visible focus, no information by colour alone.
global <const> require, table, string, ipairs, tostring

local html = require("hecate.doc.internal.html")
local json = require("hecate.json")
local strings_module = require("hecate.doc.theme.strings")

local escape, attributes = html.escape, html.attributes

local M = {}

---@class hecate.doc.ResolvedLink
---@field text string
---@field url string
---@field current? boolean
---@field external? boolean

---@class hecate.doc.ResolvedNode
---@field text string
---@field url? string
---@field current? boolean  the node is the page being rendered
---@field open? boolean  a group that contains the current page
---@field items? hecate.doc.ResolvedNode[]

---@class hecate.doc.LocaleLink
---@field code string
---@field label string
---@field lang string
---@field url string
---@field current boolean

---@class hecate.doc.PageContext
---@field config hecate.doc.SiteConfig
---@field locale hecate.doc.Locale
---@field locale_links hecate.doc.LocaleLink[]
---@field strings table<string, any>
---@field title string
---@field heading? string  text of the `<h1>`; defaults to `title`
---@field description? string
---@field layout "doc"|"home"
---@field html string  rendered body
---@field content_lang string  language of the body (differs from the locale on fallback)
---@field fallback boolean
---@field top_links hecate.doc.ResolvedLink[]
---@field sidebar hecate.doc.ResolvedNode[]
---@field outline hecate.doc.Heading[]
---@field previous? { title: string, url: string }
---@field next? { title: string, url: string }
---@field edit_url? string
---@field last_updated? string
---@field hecate_version? string
---@field lua_version? string
---@field actions? { text: string, url: string, primary: boolean }[]
---@field canonical? string
---@field alternates { lang: string, url: string }[]
---@field footer_text? string  site footer, defaults to the interface string
---@field home_url string
---@field search_index_url string
---@field asset fun(path: string): string  URL of a theme asset or root file

local ICONS = {
  search = "<circle cx=\"11\" cy=\"11\" r=\"6.5\"/><path d=\"M16 16l5 5\"/>",
  sun = "<circle cx=\"12\" cy=\"12\" r=\"4\"/><path d=\"M12 2.5v2.5M12 19v2.5M2.5 12H5M19 12h2.5M5.3 5.3l1.8 1.8M16.9 16.9l1.8 1.8M5.3 18.7l1.8-1.8M16.9 7.1l1.8-1.8\"/>",
  moon = "<path d=\"M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z\"/>",
  menu = "<path d=\"M4 7h16M4 12h16M4 17h16\"/>",
  close = "<path d=\"M6 6l12 12M18 6L6 18\"/>",
  globe = "<circle cx=\"12\" cy=\"12\" r=\"9\"/><path d=\"M3 12h18M12 3c2.5 2.7 3.8 5.7 3.8 9s-1.3 6.3-3.8 9c-2.5-2.7-3.8-5.7-3.8-9S9.5 5.7 12 3z\"/>",
  chevron = "<path d=\"M6 9l6 6 6-6\"/>",
  edit = "<path d=\"M4 20h4L19 9l-4-4L4 16v4zM13.5 6.5l4 4\"/>",
  sidebar = "<path d=\"M4 6h16M4 12h10M4 18h16\"/>",
}

-- The GitHub mark (Octicons "mark-github", MIT licence, GitHub Inc.); see THIRD_PARTY_NOTICES.
local GITHUB_PATH = "M8 0c4.42 0 8 3.58 8 8a8.013 8.013 0 0 1-5.45 7.59c-.4.08-.55-.17-.55-.38 0-.27.01-1.13.01-2.2 0-.75-.25-1.23-.54-1.48 1.78-.2 3.65-.88 3.65-3.95 0-.88-.31-1.59-.82-2.15.08-.2.36-1.02-.08-2.12 0 0-.67-.22-2.2.82-.64-.18-1.32-.27-2-.27-.68 0-1.36.09-2 .27-1.53-1.03-2.2-.82-2.2-.82-.44 1.1-.16 1.92-.08 2.12-.51.56-.82 1.28-.82 2.15 0 3.06 1.86 3.75 3.64 3.95-.23.2-.44.55-.51 1.07-.46.21-1.61.55-2.33-.66-.15-.24-.6-.83-1.23-.82-.67.01-.27.38.01.53.34.19.73.9.82 1.13.16.45.68 1.31 2.69.94 0 .67.01 1.3.01 1.49 0 .21-.15.45-.55.38A7.995 7.995 0 0 1 0 8c0-4.42 3.58-8 8-8Z"

local function icon(name, class)
  return ("<svg class=\"icon%s\" viewBox=\"0 0 24 24\" aria-hidden=\"true\" focusable=\"false\">%s</svg>"):format(
    class and (" " .. class) or "", ICONS[name])
end

local function github_icon()
  return "<svg class=\"icon icon-fill\" viewBox=\"0 0 16 16\" aria-hidden=\"true\" focusable=\"false\"><path d=\""
    .. GITHUB_PATH .. "\"/></svg>"
end

local function header(context)
  local s = context.strings
  local parts = {}
  local function add(text) parts[#parts + 1] = text end
  add("<header class=\"site-header\"><div class=\"header-inner\">")
  add(("<a class=\"logo\" href=\"%s\" aria-label=\"%s\">"):format(escape(context.home_url),
    escape(context.config.title .. ", " .. s.home)))
  add(("<img class=\"logo-light\" src=\"%s\" alt=\"\" width=\"160\" height=\"45\">"):format(
    escape(context.asset("assets/brand/hecate-logo-horizontal.svg"))))
  add(("<img class=\"logo-dark\" src=\"%s\" alt=\"\" width=\"160\" height=\"45\">"):format(
    escape(context.asset("assets/brand/hecate-logo-horizontal-on-dark.svg"))))
  add("</a>")
  add(("<button class=\"search-button\" type=\"button\" data-search-open aria-haspopup=\"dialog\">%s"
    .. "<span class=\"label\">%s</span><kbd class=\"search-shortcut\">Ctrl K</kbd></button>"):format(
    icon("search"), escape(s.search)))
  add("<span class=\"header-spacer\"></span>")
  add("<div class=\"header-panel\" id=\"header-panel\">")
  add(("<nav class=\"top-nav\" aria-label=\"%s\">"):format(escape(s.main_navigation)))
  for _, link in ipairs(context.top_links) do
    add(("<a href=\"%s\"%s>%s</a>"):format(escape(link.url), link.current and " aria-current=\"true\"" or "",
      escape(link.text)))
  end
  add("</nav>")
  if #context.locale_links > 1 then
    add("<span class=\"header-divider\" aria-hidden=\"true\"></span>")
    add(("<details class=\"locale-menu\"><summary aria-label=\"%s\">%s<span>%s</span>%s</summary><ul>"):format(
      escape(s.language), icon("globe"), escape(context.locale.label), icon("chevron")))
    for _, locale in ipairs(context.locale_links) do
      add(("<li><a href=\"%s\" lang=\"%s\" hreflang=\"%s\"%s>%s</a></li>"):format(escape(locale.url),
        escape(locale.lang), escape(locale.lang), locale.current and " aria-current=\"true\"" or "",
        escape(locale.label)))
    end
    add("</ul></details>")
  end
  add("<span class=\"header-divider\" aria-hidden=\"true\"></span>")
  add("<div class=\"header-actions\">")
  add(("<button class=\"icon-button theme-toggle\" type=\"button\" aria-label=\"%s\">%s%s</button>"):format(
    escape(s.switch_to_dark), icon("sun", "icon-sun"), icon("moon", "icon-moon")))
  if context.config.repository then
    add(("<a class=\"icon-button\" href=\"%s\" aria-label=\"%s\">%s</a>"):format(
      escape(context.config.repository), escape(s.repository), github_icon()))
  end
  add("</div></div>")
  add(("<button class=\"icon-button menu-toggle\" type=\"button\" aria-controls=\"header-panel\" "
    .. "aria-label=\"%s\">%s</button>"):format(escape(s.toggle_menu), icon("menu")))
  add("</div></header>")
  return table.concat(parts)
end

local function sidebar_list(nodes, depth)
  local out = { "<ul>" }
  for _, node in ipairs(nodes) do
    if node.items then
      out[#out + 1] = ("<li><details%s><summary>%s</summary>%s</details></li>"):format(
        node.open and " open" or "", escape(node.text), sidebar_list(node.items, depth + 1))
    else
      out[#out + 1] = ("<li><a href=\"%s\"%s>%s</a></li>"):format(escape(node.url),
        node.current and " aria-current=\"page\"" or "", escape(node.text))
    end
  end
  out[#out + 1] = "</ul>"
  return table.concat(out)
end

local function sidebar(context)
  local out = { ("<aside class=\"sidebar\" id=\"sidebar\"><nav aria-label=\"%s\">"):format(
    escape(context.strings.sidebar_navigation)) }
  for _, group in ipairs(context.sidebar) do
    if group.items then
      out[#out + 1] = "<div class=\"sidebar-group\">"
      if group.url then
        out[#out + 1] = ("<p class=\"sidebar-title\"><a href=\"%s\"%s>%s</a></p>"):format(escape(group.url),
          group.current and " aria-current=\"page\"" or "", escape(group.text))
      else
        out[#out + 1] = ("<p class=\"sidebar-title\">%s</p>"):format(escape(group.text))
      end
      out[#out + 1] = sidebar_list(group.items, 1)
      out[#out + 1] = "</div>"
    else
      out[#out + 1] = "<div class=\"sidebar-group\">" .. sidebar_list({ group }, 1) .. "</div>"
    end
  end
  out[#out + 1] = "</nav></aside><div class=\"scrim\" aria-hidden=\"true\"></div>"
  return table.concat(out)
end

local function outline(context)
  local out = { ("<aside class=\"outline\" id=\"outline\"><nav aria-labelledby=\"outline-title\">"
    .. "<h2 class=\"outline-title\" id=\"outline-title\">%s</h2><ul>"):format(escape(context.strings.on_this_page)) }
  for _, heading in ipairs(context.outline) do
    out[#out + 1] = ("<li class=\"level-%d\"><a href=\"#%s\">%s</a></li>"):format(heading.level,
      escape(heading.id), escape(heading.text))
  end
  out[#out + 1] = "</ul></nav></aside>"
  return table.concat(out)
end

local function local_nav(context, has_sidebar, has_outline)
  local s = context.strings
  local out = { "<div class=\"local-nav\"><div class=\"local-nav-inner\">" }
  if has_sidebar then
    out[#out + 1] = ("<button class=\"sidebar-toggle\" type=\"button\" aria-controls=\"sidebar\">%s<span>%s</span></button>")
      :format(icon("sidebar"), escape(s.sidebar_menu))
  end
  if has_outline then
    out[#out + 1] = ("<button class=\"outline-toggle\" type=\"button\" aria-controls=\"outline\"><span>%s</span>%s</button>")
      :format(escape(s.on_this_page), icon("chevron"))
  end
  out[#out + 1] = "</div></div>"
  return table.concat(out)
end

local function doc_footer(context)
  local s = context.strings
  local out = { "<footer class=\"doc-footer\">" }
  local meta = {}
  if context.edit_url then
    meta[#meta + 1] = ("<a class=\"edit-link\" href=\"%s\">%s%s</a>"):format(escape(context.edit_url),
      icon("edit"), escape(s.edit_page))
  end
  if context.last_updated then
    local text, date = strings_module.format_date(context.last_updated, s)
    if text then
      meta[#meta + 1] = ("<p class=\"last-updated\">%s: <time datetime=\"%s\">%s</time></p>")
        :format(escape(s.last_updated), escape(date), escape(text))
    end
  end
  if #meta > 0 then out[#out + 1] = "<div class=\"doc-footer-meta\">" .. table.concat(meta) .. "</div>" end
  if context.previous or context.next then
    out[#out + 1] = ("<nav class=\"pager\" aria-label=\"%s\">"):format(escape(s.pagination))
    if context.previous then
      out[#out + 1] = ("<a class=\"pager-card pager-prev\" rel=\"prev\" href=\"%s\"><span class=\"pager-label\">%s</span>"
        .. "<span class=\"pager-title\">%s</span></a>"):format(escape(context.previous.url),
        escape(s.previous_page), escape(context.previous.title))
    end
    if context.next then
      out[#out + 1] = ("<a class=\"pager-card pager-next\" rel=\"next\" href=\"%s\"><span class=\"pager-label\">%s</span>"
        .. "<span class=\"pager-title\">%s</span></a>"):format(escape(context.next.url), escape(s.next_page),
        escape(context.next.title))
    end
    out[#out + 1] = "</nav>"
  end
  out[#out + 1] = "</footer>"
  return table.concat(out)
end

local function search_dialog(context)
  local s = context.strings
  return ("<dialog class=\"search-dialog\" id=\"search-dialog\" aria-label=\"%s\">"
    .. "<div class=\"search-form\" role=\"search\">%s"
    .. "<input class=\"search-input\" type=\"search\" role=\"combobox\" aria-expanded=\"true\" "
    .. "aria-controls=\"search-results\" aria-autocomplete=\"list\" autocomplete=\"off\" spellcheck=\"false\" "
    .. "aria-label=\"%s\" placeholder=\"%s\">"
    .. "<form method=\"dialog\"><button class=\"icon-button\" aria-label=\"%s\">%s</button></form></div>"
    .. "<ul class=\"search-results\" id=\"search-results\" role=\"listbox\" aria-label=\"%s\"></ul>"
    .. "<div class=\"search-live visually-hidden\" role=\"status\" aria-live=\"polite\"></div>"
    .. "<div class=\"search-footer\"><span><kbd>&#8593;</kbd> <kbd>&#8595;</kbd> %s</span>"
    .. "<span><kbd>Enter</kbd> %s</span><span><kbd>Esc</kbd> %s</span></div></dialog>"):format(
    escape(s.search), icon("search"), escape(s.search), escape(s.search), escape(s.close), icon("close"),
    escape(s.search), escape(s.search_navigate), escape(s.search_select), escape(s.search_close))
end

local function head(context, title)
  local out = {
    "<meta charset=\"utf-8\">",
    "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
    ("<title>%s</title>"):format(escape(title)),
    "<meta name=\"color-scheme\" content=\"light dark\">",
    ("<link rel=\"icon\" href=\"%s\" type=\"image/svg+xml\">"):format(escape(context.asset("assets/brand/favicon.svg"))),
  }
  if context.description and context.description ~= "" then
    out[#out + 1] = ("<meta name=\"description\" content=\"%s\">"):format(escape(context.description))
    out[#out + 1] = ("<meta property=\"og:description\" content=\"%s\">"):format(escape(context.description))
  end
  out[#out + 1] = ("<meta property=\"og:title\" content=\"%s\">"):format(escape(title))
  out[#out + 1] = ("<meta property=\"og:site_name\" content=\"%s\">"):format(escape(context.config.title))
  out[#out + 1] = "<meta property=\"og:type\" content=\"website\">"
  if context.canonical then
    out[#out + 1] = ("<link rel=\"canonical\" href=\"%s\">"):format(escape(context.canonical))
  end
  for _, alternate in ipairs(context.alternates) do
    out[#out + 1] = ("<link rel=\"alternate\" hreflang=\"%s\" href=\"%s\">"):format(escape(alternate.lang),
      escape(alternate.url))
  end
  for _, font in ipairs({ "stix-two-text-latin-400-normal", "fira-sans-latin-400-normal" }) do
    out[#out + 1] = ("<link rel=\"preload\" href=\"%s\" as=\"font\" type=\"font/woff2\" crossorigin>"):format(
      escape(context.asset("assets/fonts/" .. font .. ".woff2")))
  end
  out[#out + 1] = ("<link rel=\"stylesheet\" href=\"%s\">"):format(escape(context.asset("assets/theme.css")))
  out[#out + 1] = ("<script src=\"%s\"></script>"):format(escape(context.asset("assets/theme-init.js")))
  return table.concat(out, "\n")
end

local function script_config(context)
  local s = context.strings
  local keys = { "switch_to_dark", "switch_to_light", "copy", "copy_code", "copied", "copy_failed", "table",
    "search_hint", "no_results", "results", "search_failed" }
  local subset = {}
  for _, key in ipairs(keys) do subset[key] = s[key] end
  -- `<`, `>` and `&` are written as escapes so that the text cannot close the script element.
  local text = json.encode({
    base = context.config.base, locale = context.locale.code, index = context.search_index_url, strings = subset,
  }, { canonical = true }):gsub("[<>&]", function(char) return ("\\u%04x"):format(char:byte()) end)
  return ("<script type=\"application/json\" id=\"doc-config\">%s</script>"):format(text)
end

--- Renders a documentation page to a complete HTML document.
---@param context hecate.doc.PageContext
---@return string
function M.page(context)
  local s = context.strings
  local is_home = context.layout == "home"
  local has_sidebar = not is_home and #context.sidebar > 0
  local has_outline = not is_home and #context.outline > 0
  local title = context.title
  if not is_home then title = title .. " | " .. context.config.title end
  local body = {}
  local function add(text) body[#body + 1] = text end
  add(("<a class=\"skip-link\" href=\"#content\">%s</a>"):format(escape(s.skip_to_content)))
  add(header(context))
  add(local_nav(context, has_sidebar, has_outline))
  add(("<div class=\"layout %s %s\">"):format(has_sidebar and "has-sidebar" or "no-sidebar",
    has_outline and "has-outline" or "no-outline"))
  if has_sidebar then add(sidebar(context)) end
  add("<main id=\"content\" tabindex=\"-1\">")
  if is_home then
    add("<section class=\"hero\">")
    add(("<h1 class=\"hero-title\">%s</h1>"):format(escape(context.heading or context.title)))
    if context.description and context.description ~= "" then
      add(("<p class=\"hero-tagline\">%s</p>"):format(escape(context.description)))
    end
    if context.actions and #context.actions > 0 then
      add("<div class=\"hero-actions\">")
      for _, action in ipairs(context.actions) do
        add(("<a class=\"button%s\" href=\"%s\">%s</a>"):format(action.primary and " button-primary" or "",
          escape(action.url), escape(action.text)))
      end
      add("</div>")
    end
    add("</section><div class=\"hero-pattern\" aria-hidden=\"true\"></div>")
  end
  add("<div class=\"doc-grid\"><div class=\"doc\"><article class=\"doc-content\">")
  if context.fallback then
    add(("<p class=\"notice\" role=\"note\">%s</p>"):format(escape(s.fallback_notice)))
  end
  add(("<div lang=\"%s\">"):format(escape(context.content_lang)))
  if not is_home then
    add(("<h1 class=\"page-title\">%s</h1>"):format(escape(context.heading or context.title)))
    if context.hecate_version or context.lua_version then
      add(("<p class=\"page-meta\">%s</p>"):format(escape(s.written_for:format(context.hecate_version or "?",
        context.lua_version or "?"))))
    end
  end
  add(context.html)
  add("</div></article>")
  if not is_home then add(doc_footer(context)) end
  add("</div>")
  if has_outline then add(outline(context)) end
  add("</div></main></div>")
  add(("<footer class=\"site-footer\"><p>%s</p></footer>"):format(escape(
    context.footer_text or s.footer)))
  add(search_dialog(context))
  add(script_config(context))
  add(("<script src=\"%s\" defer></script>"):format(escape(context.asset("assets/theme.js"))))
  return ("<!doctype html>\n<html lang=\"%s\">\n<head>\n%s\n</head>\n<body%s>\n%s\n</body>\n</html>\n"):format(
    escape(context.locale.lang), head(context, title), attributes({ class = is_home and "home" or "doc-page" }),
    table.concat(body, "\n"))
end

--- Renders the not-found page (`404.html`).
---@param context hecate.doc.PageContext  a context whose `html` is ignored
---@return string
function M.not_found(context)
  local s = context.strings
  context.title = s.not_found_title
  context.html = ("<p>%s</p><p><a href=\"%s\">%s</a></p>"):format(escape(s.not_found_text),
    escape(context.home_url), escape(s.not_found_link))
  context.layout, context.sidebar, context.outline = "doc", {}, {}
  context.previous, context.next, context.edit_url, context.last_updated = nil, nil, nil, nil
  context.fallback = false
  return M.page(context)
end

return M
