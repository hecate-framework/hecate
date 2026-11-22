-- Site: reads the content tree (`<guides_dir>/<locale>/**/*.md`), renders every page for every
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
local options_module = require("hecate.doc.internal.options")
local paths = require("hecate.doc.internal.paths")
local portable = require("hecate.doc.internal.portable_name")
local Page = require("hecate.doc.page")

--- Name of the marker file that identifies an output directory written by the builder.
local MARKER = ".hecate-doc-output"

---@class hecate.doc.SiteOptions
---@field site_configuration hecate.doc.SiteConfiguration  site configuration (validated by `hecate.doc.config`)
---@field guides_dir string  content root: contains one directory per locale, and optionally `public/`
---@field file_system hecate.doc.FileSystem  where the guides are read from
---@field last_updated? fun(path: string): string?  ISO 8601 date of the last change of a source file
---@field theme_file_system? hecate.doc.FileSystem  where the theme's static files are read from (default: read with `io`)
---@field theme_files_dir? string  directory of the theme's static files (default: the theme's own)

---@class hecate.doc.Site
---@field site_configuration hecate.doc.SiteConfiguration
---@field problems string[]  broken links and similar problems found by `load`
---@overload fun(options: hecate.doc.SiteOptions): hecate.doc.Site
local Site = core.class("Site")

--- Creates a site; call `load` to read and render the content.
---@param options hecate.doc.SiteOptions
function Site:init(options)
  if type(options) ~= "table" or type(options.guides_dir) ~= "string" or options.file_system == nil then
    error(core.ArgumentError("doc.Site: expects { site_configuration, guides_dir, file_system }"), 3)
  end
  options_module.check("doc.Site", "build", options, options_module.SITE, 3)
  self.site_configuration = config_module.normalise(options.site_configuration)
  self._guides_dir = (paths.separators(options.guides_dir):gsub("/+$", ""))
  self._fs = options.file_system
  self._last_updated = options.last_updated
  self._theme_file_system = options.theme_file_system
  self._theme_files_dir = options.theme_files_dir
  self._files = {} -- locale -> { pages = { id -> file }, assets = { relative -> file } }
  self._pages = {} -- locale -> { id -> Page }
  self._locale_codes = {}
  for index, locale in ipairs(self.site_configuration.locales) do self._locale_codes[index] = locale.code end
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

-- The limits of the walk of a content tree, which is data of the project: the levels of directories below the
-- root of a walk and the entries (files and directories) it meets. A tree that goes beyond is cut with a problem.
-- The table is exposed as `Site.LIMITS` and read when a walk starts (tests lower it).
local LIMITS = { depth = 32, entries = 100000 }

--- Walks the tree below `root` in the order of the names. Hidden entries (a name that starts with `.`) and the names
--- `skip_name` accepts are left out silently; a symbolic link (a file, a directory, a cycle) is never followed and is a
--- problem; a tree deeper or larger than the limits is cut with a problem. `visit_file(entry, relative, path)` gets every
--- other file. `label` names the tree in the messages (`en`, `public`).
local function walk(self, root, label, visit_file, skip_name)
  local count, stopped = 0, false
  local function visit(directory, relative, depth)
    local entries = self._fs:list(directory)
    if not entries then return end
    for _, entry in ipairs(entries) do
      if stopped then return end
      count = count + 1
      if count > LIMITS.entries then
        stopped = true
        note(self, ("%s: more than %d entries: the rest of the tree is not read"):format(label, LIMITS.entries))
        return
      end
      local child = relative == "" and entry.name or (relative .. "/" .. entry.name)
      local path = directory .. "/" .. entry.name
      if entry.name:sub(1, 1) == "." or (skip_name and skip_name(entry.name)) then
        -- hidden files and excluded names are not part of the site
      elseif entry.is_link then
        note(self, ("%s/%s is a symbolic link: links are not followed, so it is not published (copy the file or the directory into the tree)")
          :format(label, child))
      elseif entry.is_directory then
        if depth + 1 > LIMITS.depth then
          note(self, ("%s/%s is deeper than %d levels: it is not read"):format(label, child, LIMITS.depth))
        else
          visit(path, child, depth + 1)
        end
      else
        visit_file(entry, child, path)
      end
    end
  end
  visit(root, "", 0)
end

--- Fails when the output path `path` (of the source named `label`) collides with one already in `namespace`. `source_kind`
--- is "page" for the output file of a page: two pages with one URL are reported later, with the URL.
local function claim(namespace, path, label, source_kind, source)
  local kind, other = namespace:claim(path, label, source_kind)
  if kind == "same" and source_kind == "page" and other.kind == "page" then return end
  if kind == "case" then
    fail(("%s and %s differ only by case: the output files %s and %s are one file on a case-insensitive file system"):format(
      other.label, label, other.path, path), source)
  elseif kind == "same" then
    fail(("%s and %s are written to the same output file %s"):format(other.label, label, path), source)
  elseif kind then
    fail(("%s (output %s) and %s (output %s) cannot both be written: one is a file where the other needs a directory"):format(
      other.label, other.path, label, path), source)
  end
end

--- Reports the length limits a path goes beyond (problems, and errors under `fail_on_problems`), once for the file.
local function note_limits(self, checked, label)
  for _, limit in ipairs(checked.limits) do note(self, ("%s: %s"):format(label, limit)) end
end

--- Lists the pages and the other files below `directory`. Every name goes through `portable_name`: it must be a valid
--- file name on Windows, is compared in NFC (UAX #15: a tree authored on macOS may carry decomposed names) and by its
--- case-fold key over the pages and the other files together (a case-insensitive file system, macOS and Windows,
--- makes `A.md` and `a.md`, or `Img/a.svg` and `img/a.svg`, one file; a file `a` and a page or a directory `a/` cannot
--- both be written). The `.md` suffix and `exclude_file_names` are matched without regard to case, for the same reason.
local function scan(self, locale)
  local excluded = {}
  for _, name in ipairs(self.site_configuration.exclude_file_names) do excluded[portable.key(name)] = true end
  local pages, assets = {}, {}
  local namespace = portable.namespace()
  walk(self, self._guides_dir .. "/" .. locale, locale, function(entry, child, path)
    local relative = locale .. "/" .. child
    if portable.is_markdown(entry.name) then
      local written = child:sub(1, -4)
      -- A page id becomes a directory name of the output, so it must be a valid file name on every platform.
      local checked = portable.portable_name(written)
      if checked.problem then
        fail(("%s: the page id %q is not portable: %s"):format(relative, written, checked.problem), path)
      end
      note_limits(self, checked, relative)
      local id = checked.name
      if pages[id] then
        fail(("pages %s and %s differ only in Unicode normalisation (NFC and NFD): they are one page"):format(
          pages[id].relative, relative), path)
      end
      claim(namespace, output_path(locale, id), relative, "page", path)
      pages[id] = { id = id, path = path, relative = relative, locale = locale }
    else
      -- Files next to the pages are named in NFC like the pages (a link is normalised the same way).
      local checked = portable.portable_name(child)
      if checked.problem then
        fail(("%s: the file name %q is not portable: %s"):format(relative, child, checked.problem), path)
      end
      note_limits(self, checked, relative)
      local name = checked.name
      if assets[name] then
        fail(("files %s and %s differ only in Unicode normalisation (NFC and NFD): they are one file"):format(
          locale .. "/" .. assets[name].original, relative), path)
      end
      claim(namespace, locale .. "/" .. name, relative, "file", path)
      assets[name] = { path = path, relative = name, original = child, locale = locale }
    end
  end, function(name) return excluded[portable.key(name)] == true end)
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

local function page_url(self, locale, id) return self.site_configuration.base_path .. locale .. "/" .. encode_path(url_path(id)) end


--- Normalises a relative path below the locale directory. A path that climbs above it returns `nil` and the number of
--- levels it climbs above (1: the content root, where the locale directories are; 2 or more: out of the tree).
local function normalise_path(path)
  local parts, above = {}, 0
  for segment in path:gmatch("[^/]+") do
    if segment == ".." then
      if #parts == 0 then above = above + 1 else parts[#parts] = nil end
    elseif segment ~= "." then
      parts[#parts + 1] = segment
    end
  end
  if above > 0 then return nil, above end
  return table.concat(parts, "/")
end

local function humanise(id)
  local name = id:match("([^/]+)$") or id
  if name == "index" then name = id:match("([^/]+)/index$") or "index" end
  name = name:gsub("[-_]+", " ")
  return (name:gsub("^%l", string.upper))
end

-- Pages ---------------------------------------------------------------------------------

--- Reads a page source once: its text must be UTF-8 and its front matter must parse. Sets `file.meta` and `file.body`.
--- The front matter key `audience` is refused: the audience of a page is the content tree it lies in (OQ-144).
local function read_page(self, file)
  if file.meta then return file end
  local source = read_required(self, file.path)
  if #source > markdown.MAX_INPUT_BYTES then
    fail(("%s is %d bytes, more than the limit of %d bytes (8 MiB) for a Markdown page"):format(file.path, #source,
      markdown.MAX_INPUT_BYTES), file.path)
  end
  local valid, position = utf8.len(source)
  if not valid then
    fail(("%s is not valid UTF-8 (invalid byte at position %d; Markdown pages are UTF-8 text)"):format(file.path,
      position), file.path)
  end
  local meta, body = front_matter.parse(source, file.path)
  if meta.audience ~= nil then
    fail(("%s: the front matter key `audience` is no longer read: the audience of a page is the content tree it lies in. "
      .. "Move the page to `<guides_dir>/<audience>/<locale>/` (`user` or `maintainer`) and delete the key"):format(file.path),
      file.path)
  end
  file.meta, file.body = meta, body
  return file
end

--- Returns the file a locale uses for a page id: its own, or the default locale's.
local function source_for(self, locale, id)
  local own = self._files[locale].pages[id]
  if own then return own, false end
  local default = self._files[self.site_configuration.default_locale].pages[id]
  if default then return default, true end
  return nil, false
end

local function link_resolver(self, locale, page_id, problems_prefix)
  local directory = page_id:match("^(.*)/[^/]*$") or ""
  local base = self.site_configuration.base_path
  return function(href)
    if href == "" or href:find("^#") or href:find("^//") or href:find("^%a[%w+.%-]*:") then return href end
    local written, suffix = href:match("^([^#?]*)(.*)$")
    if written == "" then return href end
    if written:sub(1, 1) == "/" then
      -- A browser reads `/\\host` as `//host`, a link to another host: the backslash is percent-encoded (WHATWG URL,
      -- 4.1, "special authority ignore slashes state"; RFC 3986, 2.1) and reported.
      if href:find("\\", 1, true) then
        note(self, ("%s: link %s holds a backslash: it was percent-encoded (a browser reads `/\\` as `//`, a link to another host)")
          :format(problems_prefix, href))
        written = written:gsub("\\", "%%5C")
        suffix = suffix:gsub("\\", "%%5C")
      end
      return base .. written:sub(2) .. suffix
    end
    local path = file_names.nfc(decode_path(written))
    local joined, above = normalise_path(directory == "" and path or (directory .. "/" .. path))
    if joined == nil then
      -- A relative link that climbs out of the tree (2 levels above the locale directory or more) leads to another site, such
      -- as the tree of the other audience: the builder cannot check it, so it is left as written and the browser resolves
      -- it against the URL of the page (documentation.md, "Documentation of a project"). A link that climbs to the content
      -- root only (`../fr/x.md`) stays a problem: it names a page of another locale, or a mistake.
      if above < 2 then
        note(self, ("%s: link %s leaves the locale directory"):format(problems_prefix, href))
      end
      return href
    end
    if portable.is_markdown(joined) or path:sub(-1) == "/" or not path:match("%.[%w]+$") then
      local id = portable.is_markdown(joined) and joined:sub(1, -4) or joined
      local target = (source_for(self, locale, id) and id)
        or (source_for(self, locale, id .. "/index") and id .. "/index")
        or (id == "" and source_for(self, locale, "index") and "index")
      if not target then
        note(self, ("%s: broken link %s"):format(problems_prefix, href))
        return href
      end
      return page_url(self, locale, target) .. suffix
    end
    local asset = self._files[locale].assets[joined] or self._files[self.site_configuration.default_locale].assets[joined]
    if not asset then
      note(self, ("%s: missing file %s"):format(problems_prefix, href))
      return href
    end
    return base .. locale .. "/" .. encode_path(joined) .. suffix
  end
end

-- The identifiers of the elements of the theme (layout.lua, theme.js, mermaid-init.js): a heading with one of them would
-- give two elements the same id, and a script would find the wrong one. `main` and `search` are kept for the theme too.
local RESERVED_IDS = {}
for _, name in ipairs({ "header-panel", "sidebar", "outline", "outline-title", "search-dialog", "search-results",
  "doc-config", "content", "main", "search" }) do RESERVED_IDS[name] = true end

local function reserved_id(id)
  return RESERVED_IDS[id] == true or id:find("^d?hecate%-diagram%-%d+$") ~= nil
end

local function build_page(self, locale, id)
  local file, fallback = source_for(self, locale, id)
  assert(file, "no source for page " .. id)
  local meta, body = read_page(self, file).meta, file.body
  local strings = theme.strings.for_locale(locale, self.site_configuration.interface_strings)
  local rendered = markdown.render(body, {
    labels = { note = strings.note, tip = strings.tip, warning = strings.warning, danger = strings.danger },
    resolve_link = link_resolver(self, locale, id, file.relative),
    strip_title = true,
    file = file.relative,
  })
  for _, heading in ipairs(rendered.headings) do
    if reserved_id(heading.id) then
      note(self, ("%s: the heading %q has the id %q, which the theme uses for one of its own elements; give it another id with {#another-id}")
        :format(file.relative, heading.text, heading.id))
    end
  end
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
  local default = self.site_configuration.default_locale
  for _, code in ipairs(self._locale_codes) do self._files[code] = scan(self, code) end
  if next(self._files[default].pages) == nil then
    fail(("no pages found in %s/%s"):format(self._guides_dir, default), self._guides_dir .. "/" .. default)
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
  -- A site without a home page would open on nothing: a problem that says which file to add (the page `index` of the
  -- default locale; a locale other than the default falls back to it).
  if self._pages[default].index == nil then
    note(self, ("the site has no home page in locale %s: add %s/%s/index.md"):format(default, self._guides_dir, default))
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

--- Whether a page holds a diagram: the library of the diagrams is then part of the site (ADR 0033).
---@return boolean
function Site:uses_diagrams()
  ensure_loaded(self)
  for _, code in ipairs(self._locale_codes) do
    for _, page in ipairs(self:pages(code)) do
      if page.diagrams == true then return true end
    end
  end
  return false
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
  for _, candidate in ipairs(self.site_configuration.locales) do
    if candidate.code == locale_code then locale = candidate end
  end
  local config = self.site_configuration
  local strings = theme.strings.for_locale(locale_code, config.interface_strings)
  local pages = self:pages(locale_code)
  local list = infos(pages)
  local home_url = self.site_configuration.base_path .. locale_code .. "/"
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
      url = target and target.url or (config.base_path .. candidate.code .. "/"),
      current = candidate.code == locale_code,
    }
  end

  local function asset(path) return config.base_path .. path end
  local function absolute(url) return config.site_origin and (config.site_origin .. url) or nil end

  return {
    site_configuration = config,
    locale = locale,
    locale_links = locale_links,
    strings = strings,
    top_links = top_links,
    sidebar = {},
    outline = {},
    alternates = {},
    home_url = home_url,
    search_index_url = config.base_path .. "assets/search-" .. locale_code .. ".json",
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
  local config = self.site_configuration
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
    for _, level in ipairs(config.outline_levels) do wanted[level] = true end
    for _, heading in ipairs(page.headings) do
      if wanted[heading.level] then context.outline[#context.outline + 1] = heading end
    end
  end
  if page.meta.generated then
    -- A generated page is edited where its documentation comments are: the `source` of its front matter
    -- is a repository path, not a path below the content root.
    if config.source_edit_link_template and type(page.meta.source) == "string" then
      context.edit_url = (config.source_edit_link_template:gsub("{path}", function() return page.meta.source end))
    end
  elseif config.edit_link_template then
    context.edit_url = (config.edit_link_template:gsub("{path}", function() return page.relative_path end))
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
  if config.site_origin then
    context.canonical = config.site_origin .. page.url
    for _, candidate in ipairs(config.locales) do
      local other = self._pages[candidate.code][page.id]
      if other and not other.fallback then
        context.alternates[#context.alternates + 1] = { lang = candidate.lang, url = config.site_origin .. other.url }
      end
    end
  end
  return theme.page(context)
end

local function sitemap(self)
  local urls = {}
  for _, code in ipairs(self._locale_codes) do
    for _, page in ipairs(self:pages(code)) do
      if not page.fallback then urls[#urls + 1] = self.site_configuration.site_origin .. page.url end
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
  local links = navigation.top_links(infos(list), self.site_configuration, code)
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
  local target = self.site_configuration.base_path .. self.site_configuration.default_locale .. "/"
  return ("<!doctype html>\n<html lang=\"%s\">\n<head>\n<meta charset=\"utf-8\">\n<title>%s</title>\n"
    .. "<meta http-equiv=\"refresh\" content=\"0; url=%s\">\n<link rel=\"canonical\" href=\"%s\">\n</head>\n"
    .. "<body>\n<p><a href=\"%s\">%s</a></p>\n</body>\n</html>\n"):format(
    html.escape(self.site_configuration.default_locale), html.escape(self.site_configuration.title), html.escape(target),
    html.escape(self.site_configuration.site_origin and (self.site_configuration.site_origin .. target) or target), html.escape(target),
    html.escape(self.site_configuration.title))
end

-- llms.txt and llms-full.txt (https://llmstxt.org, "Format"). Both describe the pages of the default
-- locale, in the reading order of the navigation: the pages at the root of the site first, then one section
-- per top-level section (the top navigation order, then the other sections by name).
local function one_line(text)
  return ((text:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")))
end

local function llms_sections(self)
  local code = self.site_configuration.default_locale
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
    local nodes = navigation.sidebar(section, list, self.site_configuration, code)
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
  for _, link in ipairs(navigation.top_links(list, self.site_configuration, code)) do
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
  local code = self.site_configuration.default_locale
  local root, sections = llms_sections(self)
  -- The origin ends up in a Markdown link destination: `(`, `)`, `<` and `>` would end or open it.
  local origin = self.site_configuration.site_origin
  if origin then origin = origin:gsub("[()<>]", function(char) return ("%%%02X"):format(char:byte()) end) end
  local function location(page) return origin and (origin .. page.url) or page.url end
  local function item(page)
    local title = one_line(page.title):gsub("[%[%]\\]", "\\%0")
    local text = ("- [%s](%s)"):format(title, location(page))
    if page.description and one_line(page.description) ~= "" then text = text .. ": " .. one_line(page.description) end
    return text
  end
  local head = { "# " .. one_line(self.site_configuration.title) }
  local summary = config_module.localise(self.site_configuration.description, code, code)
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
--- content, the not-found page, the sitemap (when `config.site_origin` is set), `llms.txt` and
--- `llms-full.txt` (when `generate_llms_txt` is true) and the root redirect. Returns the number
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
    -- The key is the case-fold key (`portable_name`): on a case-insensitive file system (macOS, Windows) two paths that
    -- differ only by case are one file. The pre-pass below finds the collisions before anything is written; this is
    -- the backstop for a file that no pre-pass knows.
    local key = portable.key(path)
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
  local default = self.site_configuration.default_locale
  -- The files of `public/` are listed once, before anything is written: every name goes through `portable_name`, and
  -- the configuration names, the files of the locales and the generated files are checked with them, so that a failing
  -- build leaves no partial output.
  local public_files = {}
  if self._fs:list(self._guides_dir .. "/public") then
    walk(self, self._guides_dir .. "/public", "public", function(_, relative, path)
      local checked = portable.portable_name(relative)
      if checked.problem then
        fail(("public/%s: the file name %q is not portable: %s"):format(relative, relative, checked.problem), path)
      end
      note_limits(self, checked, "public/" .. relative)
      public_files[#public_files + 1] = { name = checked.name, label = "public/" .. relative, path = path, original = relative }
    end)
  end
  local public_names = {}
  for _, file in ipairs(public_files) do public_names[file.name] = file end
  -- The files that the configuration names are in `public/`, spelt as the file is (a name that opens only on a
  -- case-insensitive file system is a broken link on the others), in NFC, and valid names.
  local named = {}
  if self.site_configuration.logo_path then
    named[#named + 1] = self.site_configuration.logo_path.light
    named[#named + 1] = self.site_configuration.logo_path.dark
  end
  if self.site_configuration.favicon_path then
    named[#named + 1] = self.site_configuration.favicon_path.light
    named[#named + 1] = self.site_configuration.favicon_path.dark
  end
  named[#named + 1] = self.site_configuration.stylesheet_path
  for _, path in ipairs(named) do
    local checked = portable.portable_name(path)
    if checked.problem then
      fail(("the file %s named by the site configuration is not portable: %s"):format(path, checked.problem), path)
    end
    note_limits(self, checked, "public/" .. path)
    if checked.name ~= path then
      fail(("the file %s named by the site configuration is not written in Unicode Normalization Form C (NFC), the form of the names of the output"):format(path), path)
    end
    if public_names[path] == nil then
      local same
      for _, file in ipairs(public_files) do
        if portable.key(file.name) == checked.key then same = file end
      end
      fail(same and ("the file %s named by the site configuration differs only by case from %s: spell it as the file is, a name that opens on macOS and Windows only is a broken link elsewhere"):format(path, same.label)
        or ("the file %s named by the site configuration is not in public/"):format(path), path)
    end
  end
  -- The output paths of the whole site, in one namespace: the generated files first (so that a file of `public/` is the
  -- one reported), then the files of every locale, then `public/`.
  local namespace = portable.namespace()
  local function reserve(path, label, kind, source)
    claim(namespace, path, label, kind, source)
  end
  reserve(MARKER, "the marker file " .. MARKER, "generated", MARKER)
  for _, code in ipairs(self._locale_codes) do
    reserve("assets/search-" .. code .. ".json", "the search index of " .. code, "generated", code)
  end
  for _, file in ipairs(theme.asset_files) do reserve("assets/" .. file, "the theme file assets/" .. file, "generated", file) end
  if self:uses_diagrams() then
    for _, file in ipairs(theme.diagram_files) do reserve("assets/" .. file, "the theme file assets/" .. file, "generated", file) end
  end
  reserve("404.html", "the not-found page 404.html", "generated", "404.html")
  reserve("index.html", "the root redirect index.html", "generated", "index.html")
  if self.site_configuration.site_origin then reserve("sitemap.xml", "the sitemap sitemap.xml", "generated", "sitemap.xml") end
  if self.site_configuration.generate_llms_txt then
    reserve("llms.txt", "llms.txt", "generated", "llms.txt")
    reserve("llms-full.txt", "llms-full.txt", "generated", "llms-full.txt")
  end
  for _, code in ipairs(self._locale_codes) do
    for _, page in ipairs(self:pages(code)) do
      reserve(output_path(code, page.id), page.relative_path, "page", page.source_path)
    end
    local seen = {}
    for relative, file in pairs(self._files[code].assets) do
      seen[relative] = true
      reserve(code .. "/" .. relative, code .. "/" .. file.original, "file", file.path)
    end
    for relative, file in pairs(self._files[default].assets) do
      if not seen[relative] then reserve(code .. "/" .. relative, default .. "/" .. file.original, "file", file.path) end
    end
  end
  for _, file in ipairs(public_files) do reserve(file.name, file.label, "public", file.path) end
  -- First, so that an interrupted build can still be cleaned by the next one.
  put(MARKER, "Written by hecate.doc. This directory is emptied by builds that ask for a clean output.\n")
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
  local theme_file_system = self._theme_file_system or {
    read = function(_, path)
      local file = io.open(path, "rb")
      if not file then return nil end
      local data = file:read("a")
      file:close()
      return data
    end,
  }
  local directory = self._theme_files_dir or theme.assets_directory()
  for _, file in ipairs(theme.asset_files) do
    local data = theme_file_system:read(directory .. "/" .. file)
    if not data then fail("missing theme file " .. file, directory .. "/" .. file) end
    put("assets/" .. file, data)
  end
  -- The library of the diagrams is written only when a page needs it (ADR 0033).
  if self:uses_diagrams() then
    for _, file in ipairs(theme.diagram_files) do
      local data = theme_file_system:read(directory .. "/" .. file)
      if not data then fail("missing theme file " .. file, directory .. "/" .. file) end
      put("assets/" .. file, data)
    end
  end
  for _, file in ipairs(public_files) do put(file.name, read_required(self, file.path)) end
  local context = context_for(self, default, nil)
  context.alternates = {}
  put("404.html", theme.not_found(context))
  if self.site_configuration.site_origin then put("sitemap.xml", sitemap(self)) end
  if self.site_configuration.generate_llms_txt then
    local short, full = llms_files(self)
    put("llms.txt", short)
    put("llms-full.txt", full)
  end
  put("index.html", redirect_page(self))
  return count
end

Site.MARKER = MARKER
Site.LIMITS = LIMITS

return core.finalise(Site)
