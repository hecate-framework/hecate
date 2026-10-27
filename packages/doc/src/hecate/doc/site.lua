-- Site: reads the content tree (`<source>/<locale>/**/*.md`), renders every page for every
-- locale, computes navigation, and produces the files of the static site. Output is a pure
-- function of the sources, the configuration and the optional last-updated provider, so
-- builds are deterministic and diff-friendly (no timestamps, sorted iteration everywhere).
--
-- Locales (documentation.md, "Translations"): `website/<locale>/` mirrors the default
-- locale's tree; a page missing in a locale is built from the default locale with a visible
-- notice. URLs are `<base><locale>/<page path>/`, written as `<page path>/index.html`.
global <const> require, assert, io, ipairs, pairs, next, table, string, tostring, tonumber, type, error

local core = require("hecate.core")
local config_module = require("hecate.doc.config")
local errors = require("hecate.doc.errors")
local front_matter = require("hecate.doc.front_matter")
local markdown = require("hecate.doc.markdown")
local navigation = require("hecate.doc.navigation")
local search = require("hecate.doc.search")
local theme = require("hecate.doc.theme")
local html = require("hecate.doc.internal.html")
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

--- Lists the pages and the other files below `directory`.
local function scan(self, locale)
  local excluded = {}
  for _, name in ipairs(self.config.exclude) do excluded[name] = true end
  local pages, assets = {}, {}
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
        local id = child:sub(1, -4)
        pages[id] = { id = id, path = path, relative = locale .. "/" .. child, locale = locale }
      else
        assets[child] = { path = path, relative = child, locale = locale }
      end
    end
  end
  visit(self._source .. "/" .. locale, "")
  return { pages = pages, assets = assets }
end

--- Path of a page below its locale, with a trailing slash ("guide/concurrency/"; "" for the
--- locale's home page).
local function url_path(id)
  if id == "index" then return "" end
  return (id:gsub("/index$", "")) .. "/"
end

local function page_url(self, locale, id) return self.config.base .. locale .. "/" .. url_path(id) end

local function output_path(locale, id) return locale .. "/" .. url_path(id) .. "index.html" end

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

--- Returns the file a locale uses for a page id: its own, or the default locale's.
local function source_for(self, locale, id)
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
    local path, suffix = href:match("^([^#?]*)(.*)$")
    if path == "" then return href end
    if path:sub(1, 1) == "/" then return base .. path:sub(2) .. suffix end
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
        note(self, ("%s: broken link %s"):format(problems_prefix, href))
        return href
      end
      return page_url(self, locale, target) .. suffix
    end
    local asset = self._files[locale].assets[joined] or self._files[self.config.default_locale].assets[joined]
    if not asset then
      note(self, ("%s: missing file %s"):format(problems_prefix, href))
      return href
    end
    return base .. locale .. "/" .. joined .. suffix
  end
end

local function build_page(self, locale, id)
  local file, fallback = source_for(self, locale, id)
  assert(file, "no source for page " .. id)
  local source = read_required(self, file.path)
  local meta, body = front_matter.parse(source, file.path)
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
        if not target:find("^%a[%w+.%-]*:") then
          local id = target:gsub("/+$", "")
          if self._pages[page.locale][id] then
            url = self._pages[page.locale][id].url
          elseif self._pages[page.locale][id .. "/index"] then
            url = self._pages[page.locale][id .. "/index"].url
          else
            note(self, ("%s: action link to missing page %s"):format(page.relative_path, target))
          end
        end
        context.actions[#context.actions + 1] = { text = text, url = url, primary = kind == "primary" }
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

--- Writes the site through `write(relative_path, data)`, in a fixed order: the marker file,
--- the pages of each locale, the search indexes, the static files of the theme and of the
--- content, the not-found page, the sitemap (when `config.url` is set) and the root
--- redirect. Returns the number of files written.
---@param write fun(path: string, data: string)
---@return integer count
function Site:emit(write)
  ensure_loaded(self)
  local count = 0
  local function put(path, data)
    write(path, data)
    count = count + 1
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
  put("index.html", redirect_page(self))
  return count
end

Site.MARKER = MARKER

return core.finalise(Site)
