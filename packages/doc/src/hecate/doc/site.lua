-- Site: reads the content tree (`<source>/<locale>/**/*.md`), renders every page for every
-- locale, computes navigation, and produces the files of the static site. Output is a pure
-- function of the sources, the configuration and the optional last-updated provider, so
-- builds are deterministic and diff-friendly (no timestamps, sorted iteration everywhere).
--
-- Locales (documentation.md, "Translations"): `website/<locale>/` mirrors the default
-- locale's tree; a page missing in a locale is built from the default locale with a visible
-- notice. URLs are `<base><locale>/<page path>/`, written as `<page path>/index.html`.
global <const> require, assert, io, ipairs, pairs, next, table, string, tostring, tonumber, type, error, utf8

local core = require("hecate.core")
local config_module = require("hecate.doc.config")
local errors = require("hecate.doc.errors")
local front_matter = require("hecate.doc.front_matter")
local markdown = require("hecate.doc.markdown")
local navigation = require("hecate.doc.navigation")
local search = require("hecate.doc.search")
local theme = require("hecate.doc.theme")
local html = require("hecate.doc.internal.html")
local file_names = require("hecate.doc.internal.page_id")
local Page = require("hecate.doc.page")

--- Name of the marker file that identifies an output directory written by the builder.
local MARKER = ".hecate-doc-output"

---@class hecate.doc.SiteOptions
---@field config hecate.doc.SiteConfig  site configuration (validated by `hecate.doc.config`)
---@field source string  content root: contains one directory per locale, and optionally `public/`
---@field fs hecate.doc.FileSystem  where the sources are read from
---@field last_updated? fun(path: string): string?  ISO 8601 date of the last change of a source file
---@field theme_fs? hecate.doc.FileSystem  where the theme's static files are read from (default: read with `io`)
---@field theme_directory? string  directory of the theme's static files (default: the theme's own)

---@class hecate.doc.Site
---@field config hecate.doc.SiteConfig
---@field problems string[]  broken links and similar problems found by `load`
---@overload fun(options: hecate.doc.SiteOptions): hecate.doc.Site
local Site = core.class("Site")

--- Creates a site; call `load` to read and render the content.
---@param options hecate.doc.SiteOptions
function Site:init(options)
  if type(options) ~= "table" or type(options.source) ~= "string" or options.fs == nil then
    error(core.ArgumentError("doc.Site: expects { config, source, fs }"), 3)
  end
  self.config = config_module.normalise(options.config)
  self._source = options.source:gsub("/+$", "")
  self._fs = options.fs
  self._last_updated = options.last_updated
  self._theme_fs = options.theme_fs
  self._theme_directory = options.theme_directory
  self._files = {} -- locale -> { pages = { id -> file }, assets = { relative -> file } }
  self._pages = {} -- locale -> { id -> Page }
  self._hidden = {} -- locale -> { id -> audience }: pages whose audience is not published (OQ-144)
  self._locale_codes = {}
  for index, locale in ipairs(self.config.locales) do self._locale_codes[index] = locale.code end
  self._loaded = false
  self.problems = {}
end

local function fail(message, path)
  error(errors.BuildError({ message = "doc.Site: " .. message, context = { path = path } }), 0)
end

local function note(self, message)
  self.problems[#self.problems + 1] = message
end

-- Content tree --------------------------------------------------------------------------

---@return string
local function read_required(self, path)
  local text = self._fs:read(path)
  if text == nil then
    error(errors.BuildError({ message = "doc.Site: cannot read " .. path, context = { path = path } }), 0)
  end
  return text
end

--- Path of a page below its locale, with a trailing slash ("guide/concurrency/"; "" for the
--- locale's home page).
local function url_path(id)
  if id == "index" then return "" end
  return (id:gsub("/index$", "")) .. "/"
end

local function output_path(locale, id) return locale .. "/" .. url_path(id) .. "index.html" end

--- Lists the pages and the other files below `directory`.
local function scan(self, locale)
  local excluded = {}
  for _, name in ipairs(self.config.exclude) do excluded[name] = true end
  local pages, assets, folded = {}, {}, {}
  local function visit(directory, relative)
    local entries = self._fs:list(directory)
    if not entries then return end
    for _, entry in ipairs(entries) do
      local child = relative == "" and entry.name or (relative .. "/" .. entry.name)
      local path = directory .. "/" .. entry.name
      if entry.name:sub(1, 1) == "." or excluded[entry.name] then
        -- hidden files and excluded names are not part of the site
      elseif entry.is_directory then
        visit(path, child)
      elseif entry.name:sub(-3) == ".md" then
        local written = child:sub(1, -4)
        -- A page id becomes a directory name of the output, so it must be a valid file name on every
        -- platform (see `internal.page_id`), and is compared in NFC: a tree authored on macOS may carry
        -- decomposed names (UAX #15).
        local problem = file_names.windows_problem(written)
        if problem then
          fail(("%s: the page id %q is not portable: %s"):format(locale .. "/" .. child, written, problem), path)
        end
        local id = file_names.nfc(written)
        if pages[id] then
          fail(("pages %s and %s differ only in Unicode normalisation (NFC and NFD): they are one page"):format(
            pages[id].relative, locale .. "/" .. child), path)
        end
        -- On macOS and Windows two ids that differ only by case are one directory of the output.
        local key = html.lower(id)
        if folded[key] then
          fail(("pages %s and %s differ only by case: the output files %s and %s are one file on a case-insensitive file system"):format(
            folded[key].relative, locale .. "/" .. child, folded[key].output, output_path(locale, id)), path)
        end
        folded[key] = { relative = locale .. "/" .. child, output = output_path(locale, id) }
        pages[id] = { id = id, path = path, relative = locale .. "/" .. child, locale = locale }
      else
        -- Files next to the pages are named in NFC like the pages (a link is normalised the same way).
        local name = file_names.nfc(child)
        if assets[name] then
          fail(("files %s and %s differ only in Unicode normalisation (NFC and NFD): they are one file"):format(
            locale .. "/" .. assets[name].original, locale .. "/" .. child), path)
        end
        assets[name] = { path = path, relative = name, original = child, locale = locale }
      end
    end
  end
  visit(self._source .. "/" .. locale, "")
  return { pages = pages, assets = assets }
end

--- Percent-encodes every byte of a URL path that is not an unreserved character or a `/` (RFC 3986, 2.3 and
--- 2.1), so that a page id with a space, `?`, `#`, `%` or non-ASCII letters is one valid path.
local function encode_path(path)
  return (path:gsub("[^%w%-._~/]", function(char) return ("%%%02X"):format(char:byte()) end))
end

--- Inverse of `encode_path` for the destination of a link written in a page (RFC 3986, 2.1).
local function decode_path(path)
  return (path:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

local function page_url(self, locale, id) return self.config.base .. locale .. "/" .. encode_path(url_path(id)) end


local function normalise_path(path)
  local parts = {}
  for segment in path:gmatch("[^/]+") do
    if segment == ".." then
      if #parts == 0 then return nil end
      parts[#parts] = nil
    elseif segment ~= "." then
      parts[#parts + 1] = segment
    end
  end
  return table.concat(parts, "/")
end

local function humanise(id)
  local name = id:match("([^/]+)$") or id
  if name == "index" then name = id:match("([^/]+)/index$") or "index" end
  name = name:gsub("[-_]+", " ")
  return (name:gsub("^%l", string.upper))
end

-- Pages ---------------------------------------------------------------------------------

--- Reads a page source once: its text must be UTF-8, its front matter must parse and its `audience`
--- (OQ-144) must be one of the audiences. Sets `file.meta`, `file.body` and `file.audience`. A page of an
--- audience that is not published is validated like any other: a mistake does not wait for the day it is published.
local function read_page(self, file)
  if file.meta then return file end
  local source = read_required(self, file.path)
  if not utf8.len(source) then
    fail(("%s is not valid UTF-8 (Markdown pages are UTF-8 text)"):format(file.path), file.path)
  end
  local meta, body = front_matter.parse(source, file.path)
  local audience = meta.audience
  if audience == nil then
    audience = self.config.default_audience
  elseif type(audience) ~= "string" or not config_module.AUDIENCES[audience] then
    fail(("%s: front matter `audience` must be \"user\" or \"maintainer\", got %s"):format(file.relative,
      type(audience) == "string" and ("%q"):format(audience) or ("a " .. type(audience))), file.path)
  end
  file.meta, file.body, file.audience = meta, body, audience
  return file
end

--- Returns the file a locale uses for a page id: its own, or the default locale's. A page whose audience is
--- not published has no source: it is absent from the site, and a link to it is a broken link.
local function source_for(self, locale, id)
  if self._hidden[locale] and self._hidden[locale][id] then return nil, false end
  local own = self._files[locale].pages[id]
  if own then return own, false end
  local default = self._files[self.config.default_locale].pages[id]
  if default then return default, true end
  return nil, false
end

local function link_resolver(self, locale, page_id, problems_prefix)
  local directory = page_id:match("^(.*)/[^/]*$") or ""
  local base = self.config.base
  return function(href)
    if href == "" or href:find("^#") or href:find("^//") or href:find("^%a[%w+.%-]*:") then return href end
    local written, suffix = href:match("^([^#?]*)(.*)$")
    if written == "" then return href end
    if written:sub(1, 1) == "/" then return base .. written:sub(2) .. suffix end
    local path = file_names.nfc(decode_path(written))
    local joined = normalise_path(directory == "" and path or (directory .. "/" .. path))
    if joined == nil then
      note(self, ("%s: link %s leaves the content root"):format(problems_prefix, href))
      return href
    end
    if joined:sub(-3) == ".md" or path:sub(-1) == "/" or not path:match("%.[%w]+$") then
      local id = joined:gsub("%.md$", "")
      local target = (source_for(self, locale, id) and id)
        or (source_for(self, locale, id .. "/index") and id .. "/index")
        or (id == "" and source_for(self, locale, "index") and "index")
      if not target then
        local hidden = self._hidden[locale] or {}
        local hidden_audience = hidden[id] or hidden[id .. "/index"] or (id == "" and hidden["index"]) or nil
        if hidden_audience then
          note(self, ("%s: link %s targets a page of the %s audience, which is not published"):format(
            problems_prefix, href, hidden_audience))
        else
          note(self, ("%s: broken link %s"):format(problems_prefix, href))
        end
        return href
      end
      return page_url(self, locale, target) .. suffix
    end
    local asset = self._files[locale].assets[joined] or self._files[self.config.default_locale].assets[joined]
    if not asset then
      note(self, ("%s: missing file %s"):format(problems_prefix, href))
      return href
    end
    return base .. locale .. "/" .. encode_path(joined) .. suffix
  end
end

local function build_page(self, locale, id)
  local file, fallback = source_for(self, locale, id)
  assert(file, "no source for page " .. id)
  local meta, body = read_page(self, file).meta, file.body
  local strings = theme.strings.for_locale(locale, self.config.strings)
  local rendered = markdown.render(body, {
    labels = { note = strings.note, tip = strings.tip, warning = strings.warning, danger = strings.danger },
    resolve_link = link_resolver(self, locale, id, file.relative),
    strip_title = true,
  })
  local title = meta.title
  if type(title) ~= "string" or title == "" then title = rendered.title end
  if not title then
    title = humanise(id)
    note(self, ("%s: no title (front matter `title` or a leading # heading)"):format(file.relative))
  end
  local layout = meta.layout == "home" and "home" or "doc"
  return Page({
    locale = locale,
    id = id,
    url = page_url(self, locale, id),
    title = title,
    heading = rendered.title or title,
    description = type(meta.description) == "string" and meta.description or nil,
    meta = meta,
    html = rendered.html,
    headings = rendered.headings,
    diagrams = rendered.diagrams,
    sections = rendered.sections,
    fallback = fallback,
    source_locale = file.locale,
    source_path = file.path,
    relative_path = file.relative,
    order = tonumber(meta.order),
    layout = layout,
  })
end

--- Reads and renders every page of every locale. Raises `hecate.doc.BuildError` on
--- malformed front matter, unreadable sources and clashing URLs; softer problems (broken
--- links, missing titles) are collected in `site.problems`.
---@return hecate.doc.Site
function Site:load()
  self.problems = {}
  local default = self.config.default_locale
  for _, code in ipairs(self._locale_codes) do self._files[code] = scan(self, code) end
  if next(self._files[default].pages) == nil then
    fail(("no pages found in %s/%s"):format(self._source, default), self._source .. "/" .. default)
  end
  -- Audiences (OQ-144): every page is read first, so that a page of an unpublished audience is known
  -- before any link is resolved. A page is hidden in a locale when its own file or the default locale's file
  -- is of an audience that is not published: a translation never publishes what the original keeps back.
  local published = {}
  for _, audience in ipairs(self.config.audiences) do published[audience] = true end
  for _, code in ipairs(self._locale_codes) do
    local pages = self._files[code].pages
    local ids_of_locale = {}
    for id in pairs(pages) do ids_of_locale[#ids_of_locale + 1] = id end
    table.sort(ids_of_locale)
    for _, id in ipairs(ids_of_locale) do read_page(self, pages[id]) end
  end
  for _, code in ipairs(self._locale_codes) do
    self._hidden[code] = {}
    for _, file in ipairs({ self._files[code].pages, self._files[default].pages }) do
      for id, entry in pairs(file) do
        if not published[entry.audience] and not self._hidden[code][id] then self._hidden[code][id] = entry.audience end
      end
    end
  end
  for _, code in ipairs(self._locale_codes) do
    local ids, seen = {}, {}
    local function add(id)
      if not seen[id] then
        seen[id] = true
        ids[#ids + 1] = id
      end
    end
    for id in pairs(self._files[default].pages) do add(id) end
    for id in pairs(self._files[code].pages) do add(id) end
    for index = #ids, 1, -1 do
      if self._hidden[code][ids[index]] then table.remove(ids, index) end
    end
    table.sort(ids)
    local urls = {}
    self._pages[code] = {}
    for _, id in ipairs(ids) do
      local url = page_url(self, code, id)
      if urls[url] then fail(("pages %s and %s have the same URL %s"):format(urls[url], id, url), id) end
      urls[url] = id
      self._pages[code][id] = build_page(self, code, id)
    end
  end
  table.sort(self.problems)
  self._loaded = true
  return self
end

local function ensure_loaded(self)
  if not self._loaded then error(core.ArgumentError("doc.Site: call Site:load() first"), 3) end
end

--- Returns the pages of a locale, sorted by id (fallback pages included).
---@param locale string
---@return hecate.doc.Page[]
function Site:pages(locale)
  ensure_loaded(self)
  local list = {}
  for _, page in pairs(self._pages[locale] or {}) do list[#list + 1] = page end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

--- Returns the pages of a locale that are not published because of their audience, sorted by id.
---@param locale string
---@return { id: string, audience: hecate.doc.Audience }[]
function Site:unpublished(locale)
  ensure_loaded(self)
  local list = {}
  for id, audience in pairs(self._hidden[locale] or {}) do list[#list + 1] = { id = id, audience = audience } end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

--- Returns one page, or nil.
---@param locale string
---@param id string
---@return hecate.doc.Page?
function Site:page(locale, id)
  ensure_loaded(self)
  return (self._pages[locale] or {})[id]
end

-- Rendering -----------------------------------------------------------------------------

local function infos(pages)
  local list = {}
  for _, page in ipairs(pages) do
    list[#list + 1] = { id = page.id, title = page.title, order = page.order }
  end
  return list
end

local function resolve_nodes(self, locale, nodes, current)
  local out, contains = {}, false
  for _, node in ipairs(nodes) do
    local resolved = { text = node.text }
    local is_current = node.link == current
    if node.link then resolved.url = page_url(self, locale, node.link) end
    resolved.current = is_current or nil
    local inner = false
    if node.items then
      resolved.items, inner = resolve_nodes(self, locale, node.items, current)
      resolved.open = (inner or is_current) or nil
    end
    contains = contains or is_current or inner
    out[#out + 1] = resolved
  end
  return out, contains
end

local function context_for(self, locale_code, page)
  local locale
  for _, candidate in ipairs(self.config.locales) do
    if candidate.code == locale_code then locale = candidate end
  end
  local config = self.config
  local strings = theme.strings.for_locale(locale_code, config.strings)
  local pages = self:pages(locale_code)
  local list = infos(pages)
  local home_url = self.config.base .. locale_code .. "/"
  local section = page and navigation.section_of(page.id)

  local top_links = {}
  for _, link in ipairs(navigation.top_links(list, config, locale_code)) do
    top_links[#top_links + 1] = {
      text = link.text,
      url = link.id and page_url(self, locale_code, link.id) or link.url,
      external = link.url ~= nil or nil,
      current = (page ~= nil and section ~= nil and link.section == section) or nil,
    }
  end

  local locale_links = {}
  for _, candidate in ipairs(config.locales) do
    local target = page and self._pages[candidate.code][page.id]
    locale_links[#locale_links + 1] = {
      code = candidate.code, label = candidate.label, lang = candidate.lang,
      url = target and target.url or (config.base .. candidate.code .. "/"),
      current = candidate.code == locale_code,
    }
  end

  local function asset(path) return config.base .. path end
  local function absolute(url) return config.url and (config.url .. url) or nil end

  return {
    config = config,
    locale = locale,
    locale_links = locale_links,
    strings = strings,
    top_links = top_links,
    sidebar = {},
    outline = {},
    alternates = {},
    home_url = home_url,
    search_index_url = config.base .. "assets/search-" .. locale_code .. ".json",
    asset = asset,
    public_url = function(path) return asset(encode_path(path)) end,
    footer_text = config_module.localise(config.footer, locale_code, config.default_locale),
    content_lang = locale.lang,
    description = config_module.localise(config.description, locale_code, config.default_locale),
    absolute = absolute,
    list = list,
    section = section,
  }
end

local function render_page(self, page)
  local context = context_for(self, page.locale, page)
  local config = self.config
  context.title = page.title
  context.heading = page.heading
  context.description = page.description or context.description
  context.layout = page.layout
  context.html = page.html
  context.diagrams = page.diagrams
  context.fallback = page.fallback
  context.hecate_version = type(page.meta.hecate) == "string" and page.meta.hecate or nil
  context.lua_version = type(page.meta.lua) == "string" and page.meta.lua or nil
  for _, candidate in ipairs(config.locales) do
    if candidate.code == page.source_locale then context.content_lang = candidate.lang end
  end
  if page.layout ~= "home" and context.section and page.meta.sidebar ~= false then
    local nodes, problems = navigation.sidebar(context.section, context.list, config, page.locale)
    for _, problem in ipairs(problems) do note(self, page.relative_path .. ": " .. problem) end
    context.sidebar = resolve_nodes(self, page.locale, nodes, page.id)
    local previous, next_id = navigation.neighbours(nodes, page.id)
    local function neighbour(id)
      local target = id and self._pages[page.locale][id]
      return target and { title = target.title, url = target.url } or nil
    end
    context.previous, context.next = neighbour(previous), neighbour(next_id)
  end
  if page.meta.outline ~= false then
    local wanted = {}
    for _, level in ipairs(config.outline) do wanted[level] = true end
    for _, heading in ipairs(page.headings) do
      if wanted[heading.level] then context.outline[#context.outline + 1] = heading end
    end
  end
  if page.meta.generated then
    -- A generated page is edited where its documentation comments are: the `source` of its front matter
    -- is a repository path, not a path below the content root.
    if config.source_edit_link and type(page.meta.source) == "string" then
      context.edit_url = (config.source_edit_link:gsub("{path}", function() return page.meta.source end))
    end
  elseif config.edit_link then
    context.edit_url = (config.edit_link:gsub("{path}", function() return page.relative_path end))
  end
  local date = page.meta.last_updated
  if date == nil and self._last_updated then date = self._last_updated(page.source_path) end
  context.last_updated = type(date) == "string" and date or nil
  if page.layout == "home" and type(page.meta.actions) == "table" then
    context.actions = {}
    for _, line in ipairs(page.meta.actions) do
      local fields = {}
      for field in (tostring(line) .. "|"):gmatch("([^|]*)|") do fields[#fields + 1] = field:match("^%s*(.-)%s*$") end
      local text, target, kind = fields[1], fields[2], fields[3]
      if text and target and target ~= "" then
        local url = target
        if html.is_safe_url(target) == false then
          url = nil
          note(self, ("%s: action link with an unsafe URL scheme %s dropped"):format(page.relative_path, target))
        elseif not target:find("^%a[%w+.%-]*:") then
          local id = file_names.nfc((target:gsub("/+$", "")))
          if self._pages[page.locale][id] then
            url = self._pages[page.locale][id].url
          elseif self._pages[page.locale][id .. "/index"] then
            url = self._pages[page.locale][id .. "/index"].url
          else
            note(self, ("%s: action link to missing page %s"):format(page.relative_path, target))
          end
        end
        if url then context.actions[#context.actions + 1] = { text = text, url = url, primary = kind == "primary" } end
      end
    end
  end
  if config.url then
    context.canonical = config.url .. page.url
    for _, candidate in ipairs(config.locales) do
      local other = self._pages[candidate.code][page.id]
      if other and not other.fallback then
        context.alternates[#context.alternates + 1] = { lang = candidate.lang, url = config.url .. other.url }
      end
    end
  end
  return theme.page(context)
end

local function sitemap(self)
  local urls = {}
  for _, code in ipairs(self._locale_codes) do
    for _, page in ipairs(self:pages(code)) do
      if not page.fallback then urls[#urls + 1] = self.config.url .. page.url end
    end
  end
  table.sort(urls)
  local out = { "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
    "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">" }
  for _, url in ipairs(urls) do out[#out + 1] = ("<url><loc>%s</loc></url>"):format(html.escape(url)) end
  out[#out + 1] = "</urlset>"
  return table.concat(out, "\n") .. "\n"
end

local function search_documents(self, code)
  local list = self:pages(code)
  local links = navigation.top_links(infos(list), self.config, code)
  local category = {}
  for _, link in ipairs(links) do
    if link.section then category[link.section] = link.text end
  end
  local out = {}
  for _, page in ipairs(list) do
    local section = navigation.section_of(page.id)
    out[#out + 1] = {
      title = page.title, url = page.url, category = section and category[section] or nil,
      sections = page.sections,
    }
  end
  return out
end

local function redirect_page(self)
  local target = self.config.base .. self.config.default_locale .. "/"
  return ("<!doctype html>\n<html lang=\"%s\">\n<head>\n<meta charset=\"utf-8\">\n<title>%s</title>\n"
    .. "<meta http-equiv=\"refresh\" content=\"0; url=%s\">\n<link rel=\"canonical\" href=\"%s\">\n</head>\n"
    .. "<body>\n<p><a href=\"%s\">%s</a></p>\n</body>\n</html>\n"):format(
    html.escape(self.config.default_locale), html.escape(self.config.title), html.escape(target),
    html.escape(self.config.url and (self.config.url .. target) or target), html.escape(target),
    html.escape(self.config.title))
end

-- llms.txt and llms-full.txt (https://llmstxt.org, "Format"). Both describe the published pages of the default
-- locale, in the reading order of the navigation: the pages at the root of the site first, then one section
-- per top-level section (the top navigation order, then the other sections by name). Pages of an audience that
-- is not published are not in `self:pages`, so they never appear.
local function one_line(text)
  return ((text:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")))
end

local function llms_sections(self)
  local code = self.config.default_locale
  local pages = self:pages(code)
  local list = infos(pages)
  local by_id, in_section, root = {}, {}, {}
  for _, page in ipairs(pages) do
    by_id[page.id] = page
    local section = navigation.section_of(page.id)
    if section then
      in_section[section] = in_section[section] or {}
      table.insert(in_section[section], page)
    else
      root[#root + 1] = page
    end
  end
  table.sort(root, function(a, b)
    if (a.id == "index") ~= (b.id == "index") then return a.id == "index" end
    local order_a, order_b = a.order or 1000, b.order or 1000
    if order_a ~= order_b then return order_a < order_b end
    return a.id < b.id
  end)
  local sections, seen = {}, {}
  local function add(section, text)
    if seen[section] or not in_section[section] then return end
    seen[section] = true
    local ordered, listed = {}, {}
    local nodes = navigation.sidebar(section, list, self.config, code)
    for _, id in ipairs(navigation.reading_order(nodes)) do
      if by_id[id] and not listed[id] then
        listed[id] = true
        ordered[#ordered + 1] = by_id[id]
      end
    end
    for _, page in ipairs(in_section[section]) do -- sorted by id
      if not listed[page.id] then ordered[#ordered + 1] = page end
    end
    sections[#sections + 1] = { text = text, pages = ordered }
  end
  for _, link in ipairs(navigation.top_links(list, self.config, code)) do
    if link.section then add(link.section, link.text) end
  end
  local others = {}
  for section in pairs(in_section) do others[#others + 1] = section end
  table.sort(others)
  for _, section in ipairs(others) do add(section, humanise(section)) end
  return root, sections
end

--- The text of `llms.txt` and of `llms-full.txt`.
local function llms_files(self)
  local code = self.config.default_locale
  local root, sections = llms_sections(self)
  local function location(page) return self.config.url and (self.config.url .. page.url) or page.url end
  local function item(page)
    local title = one_line(page.title):gsub("[%[%]\\]", "\\%0")
    local text = ("- [%s](%s)"):format(title, location(page))
    if page.description and one_line(page.description) ~= "" then text = text .. ": " .. one_line(page.description) end
    return text
  end
  local head = { "# " .. one_line(self.config.title) }
  local summary = config_module.localise(self.config.description, code, code)
  if type(summary) == "string" and one_line(summary) ~= "" then head[#head + 1] = "> " .. one_line(summary) end
  local index = table.move(head, 1, #head, 1, {})
  local ordered = {}
  local function list(pages)
    local lines = {}
    for _, page in ipairs(pages) do
      lines[#lines + 1] = item(page)
      ordered[#ordered + 1] = page
    end
    return table.concat(lines, "\n")
  end
  if #root > 0 then index[#index + 1] = list(root) end
  for _, section in ipairs(sections) do
    index[#index + 1] = "## " .. one_line(section.text)
    index[#index + 1] = list(section.pages)
  end
  local full = head
  for _, page in ipairs(ordered) do
    local body = read_page(self, (source_for(self, code, page.id))).body
    local first = body:find("%S")
    local last = body:match(".*()%S")
    body = first and body:sub(first, last) or ""
    full[#full + 1] = "---"
    full[#full + 1] = "Source: " .. location(page)
    -- A page whose title is in its front matter has no heading in the body: the concatenation needs one.
    if not (body:find("^#[ \t]") or body:find("^#\r?\n") or body:find("^[^\n]*\n=+[ \t]*\r?\n")) then
      full[#full + 1] = "# " .. one_line(page.title)
    end
    full[#full + 1] = body
  end
  return table.concat(index, "\n\n") .. "\n", table.concat(full, "\n\n") .. "\n"
end

--- Writes the site through `write(relative_path, data)`, in a fixed order: the marker file,
--- the pages of each locale, the search indexes, the static files of the theme and of the
--- content, the not-found page, the sitemap (when `config.url` is set), `llms.txt` and
--- `llms-full.txt` (when `config.llms` is true) and the root redirect. Returns the number
--- of files written.
---@param write fun(path: string, data: string)
---@return integer count
function Site:emit(write)
  ensure_loaded(self)
  local count = 0
  local written = {}
  local function put(path, data)
    -- A file of `public/` that has the path of a generated file is refused, never overwritten (or
    -- overwriting a generated file): generated pages are never replaced by hand-made files.
    -- The key is case-folded: on a case-insensitive file system (macOS, Windows) two paths that differ only
    -- by case are one file.
    local key = path:lower()
    if written[key] then
      local other = written[key]
      fail(other == path
        and ("the output file %s is written twice: a file of public/ or of a locale directory collides with a generated file"):format(path)
        or ("the output files %s and %s differ only by case: they are one file on a case-insensitive file system"):format(other, path),
        path)
    end
    written[key] = path
    write(path, data)
    count = count + 1
  end
  -- The files that the configuration names are checked before anything is written: a failing build leaves
  -- no partial output.
  local named = {}
  if self.config.logo then
    named[#named + 1] = self.config.logo.light
    named[#named + 1] = self.config.logo.dark
  end
  if self.config.favicon then
    named[#named + 1] = self.config.favicon.light
    named[#named + 1] = self.config.favicon.dark
  end
  named[#named + 1] = self.config.theme
  for _, path in ipairs(named) do
    if self._fs:read(self._source .. "/public/" .. path) == nil then
      fail(("the file %s named by the site configuration is not in public/"):format(path), path)
    end
  end
  -- First, so that an interrupted build can still be cleaned by the next one.
  put(MARKER, "Written by hecate.doc. This directory is emptied by builds that ask for a clean output.\n")
  local default = self.config.default_locale
  for _, code in ipairs(self._locale_codes) do
    for _, page in ipairs(self:pages(code)) do put(output_path(code, page.id), render_page(self, page)) end
    local index = search.build(code, search_documents(self, code))
    put("assets/search-" .. code .. ".json", search.encode(index))
    -- Files next to the pages (images and so on), with fallback to the default locale.
    local assets, seen = {}, {}
    for relative, file in pairs(self._files[code].assets) do
      assets[#assets + 1] = file
      seen[relative] = true
    end
    for relative, file in pairs(self._files[default].assets) do
      if not seen[relative] then assets[#assets + 1] = file end
    end
    table.sort(assets, function(a, b) return a.relative < b.relative end)
    for _, file in ipairs(assets) do put(code .. "/" .. file.relative, read_required(self, file.path)) end
  end
  -- The theme's own files are read with `io` (no directory listing), so that a build on an
  -- in-memory tree needs no reactor.
  local theme_fs = self._theme_fs or {
    read = function(_, path)
      local file = io.open(path, "rb")
      if not file then return nil end
      local data = file:read("a")
      file:close()
      return data
    end,
  }
  local directory = self._theme_directory or theme.assets_directory()
  for _, file in ipairs(theme.asset_files) do
    local data = theme_fs:read(directory .. "/" .. file)
    if not data then fail("missing theme file " .. file, directory .. "/" .. file) end
    put("assets/" .. file, data)
  end
  -- The library of the diagrams is written only when a page needs it (ADR 0033).
  local diagrams = false
  for _, code in ipairs(self._locale_codes) do
    for _, page in ipairs(self:pages(code)) do diagrams = diagrams or page.diagrams == true end
  end
  if diagrams then
    for _, file in ipairs(theme.diagram_files) do
      local data = theme_fs:read(directory .. "/" .. file)
      if not data then fail("missing theme file " .. file, directory .. "/" .. file) end
      put("assets/" .. file, data)
    end
  end
  local public = self._fs:list(self._source .. "/public")
  if public then
    local function visit(path, relative)
      for _, entry in ipairs(self._fs:list(path) or {}) do
        local child = relative == "" and entry.name or (relative .. "/" .. entry.name)
        if entry.is_directory then visit(path .. "/" .. entry.name, child)
        elseif entry.name:sub(1, 1) ~= "." then put(child, read_required(self, path .. "/" .. entry.name)) end
      end
    end
    visit(self._source .. "/public", "")
  end
  local context = context_for(self, default, nil)
  context.alternates = {}
  put("404.html", theme.not_found(context))
  if self.config.url then put("sitemap.xml", sitemap(self)) end
  if self.config.llms then
    local short, full = llms_files(self)
    put("llms.txt", short)
    put("llms-full.txt", full)
  end
  put("index.html", redirect_page(self))
  return count
end

Site.MARKER = MARKER

return core.finalise(Site)
