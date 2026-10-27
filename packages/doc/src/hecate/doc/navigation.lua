-- Navigation model: top links, the sidebar of a section and the previous/next pages.
-- Pure functions over page descriptions, so they are tested without rendering anything.
global <const> require, type, ipairs, pairs, table, string

local config_module = require("hecate.doc.config")

--- Sidebar, previous/next and top links, as pure functions.
---@class hecate.doc.navigation
local M = {}

---@class hecate.doc.PageInfo
---@field id string  path without extension, relative to the locale root ("guide/concurrency")
---@field title string
---@field order? number  front matter `order`, smaller first (default 1000)

---@class hecate.doc.SidebarNode
---@field text string
---@field link? string  page id
---@field items? hecate.doc.SidebarNode[]  children; a node with `items` is a group

---@class hecate.doc.TopLink
---@field text string
---@field id? string  target page id, when the link points inside the site
---@field url? string  absolute URL, for external links
---@field section? string  top-level section the link belongs to

local DEFAULT_ORDER = 1000

--- Returns the top-level section of a page id ("reference/x" gives "reference"; a page
--- at the root has none).
---@param id string
---@return string?
function M.section_of(id) return id:match("^([^/]+)/") end

local function humanise(name)
  name = name:gsub("[-_]+", " ")
  return (name:gsub("^%l", string.upper))
end

local function sort_key(a, b)
  local order_a, order_b = a.order or DEFAULT_ORDER, b.order or DEFAULT_ORDER
  if order_a ~= order_b then return order_a < order_b end
  local text_a, text_b = a.text:lower(), b.text:lower()
  if text_a ~= text_b then return text_a < text_b end
  return (a.link or a.key or "") < (b.link or b.key or "")
end

--- Builds the nodes of one directory of the page tree. `prefix` is "" or ends with "/".
local function directory_nodes(by_id, ids, prefix)
  local leaves, directories = {}, {}
  for _, id in ipairs(ids) do
    if id:sub(1, #prefix) == prefix then
      local rest = id:sub(#prefix + 1)
      local directory = rest:match("^([^/]+)/")
      if directory then
        directories[directory] = true
      elseif rest ~= "index" then
        local page = by_id[id]
        leaves[#leaves + 1] = { text = page.title, link = id, order = page.order, key = id }
      end
    end
  end
  local nodes = leaves
  local names = {}
  for name in pairs(directories) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    local path = prefix .. name .. "/"
    local index = by_id[path .. "index"]
    nodes[#nodes + 1] = {
      text = index and index.title or humanise(name),
      link = index and index.id or nil,
      items = directory_nodes(by_id, ids, path),
      order = index and index.order or nil,
      key = path,
    }
  end
  table.sort(nodes, sort_key)
  return nodes
end

local function clean(nodes)
  for _, node in ipairs(nodes) do
    node.order, node.key = nil, nil
    if node.items then clean(node.items) end
  end
  return nodes
end

---@param by_id table<string, hecate.doc.PageInfo>
---@param items (string|hecate.doc.SidebarItem)[]
---@param locale string
---@param default_locale string
---@param problems string[]
---@return hecate.doc.SidebarNode[]
local function explicit_nodes(by_id, items, locale, default_locale, problems)
  local out = {}
  for _, item in ipairs(items) do
    if type(item) == "string" then
      local page = by_id[item]
      if page then
        out[#out + 1] = { text = page.title, link = page.id }
      else
        problems[#problems + 1] = ("sidebar: no page %s"):format(item)
      end
    else
      local page = item.link and by_id[item.link]
      if item.link and not page then problems[#problems + 1] = ("sidebar: no page %s"):format(item.link) end
      local node = {
        text = config_module.localise(item.text, locale, default_locale) or (page and page.title) or "",
        link = page and page.id or nil,
      }
      if item.items then node.items = explicit_nodes(by_id, item.items, locale, default_locale, problems) end
      out[#out + 1] = node
    end
  end
  return out
end

--- Computes the sidebar of a top-level section: the explicit configuration when there is
--- one (`config.sidebar[section]`), otherwise the page tree. The first group holds the
--- pages directly in the section, then each sub-directory forms a group.
---@param section string
---@param pages hecate.doc.PageInfo[]
---@param config hecate.doc.SiteConfig
---@param locale string
---@return hecate.doc.SidebarNode[] nodes
---@return string[] problems  explicit entries that name no page
function M.sidebar(section, pages, config, locale)
  local by_id, ids = {}, {}
  for _, page in ipairs(pages) do
    by_id[page.id] = page
    ids[#ids + 1] = page.id
  end
  table.sort(ids)
  local problems = {}
  local explicit = config.sidebar and config.sidebar[section]
  if explicit then
    return explicit_nodes(by_id, explicit, locale, config.default_locale, problems), problems
  end
  local prefix = section .. "/"
  local children = directory_nodes(by_id, ids, prefix)
  local direct, groups = {}, {}
  for _, node in ipairs(children) do
    if node.items then groups[#groups + 1] = node else direct[#direct + 1] = node end
  end
  local index = by_id[prefix .. "index"]
  local out = {}
  local heading = index and index.title or humanise(section)
  if index then table.insert(direct, 1, { text = index.title, link = index.id }) end
  if #direct > 0 or #groups == 0 then
    out[#out + 1] = { text = heading, items = direct }
  end
  for _, group in ipairs(groups) do out[#out + 1] = group end
  return clean(out), problems
end

--- Lists the page ids of a sidebar in reading order.
---@param nodes hecate.doc.SidebarNode[]
---@return string[]
function M.reading_order(nodes)
  local order = {}
  local function visit(list)
    for _, node in ipairs(list) do
      if node.link then order[#order + 1] = node.link end
      if node.items then visit(node.items) end
    end
  end
  visit(nodes)
  return order
end

--- Returns the ids of the previous and next pages of `id` in the sidebar (nil at the
--- ends, or when the page is not in the sidebar).
---@param nodes hecate.doc.SidebarNode[]
---@param id string
---@return string? previous
---@return string? next
function M.neighbours(nodes, id)
  local order = M.reading_order(nodes)
  for index, candidate in ipairs(order) do
    if candidate == id then return order[index - 1], order[index + 1] end
  end
  return nil, nil
end

--- Computes the top navigation: the configured links, or one link per top-level section.
---@param pages hecate.doc.PageInfo[]
---@param config hecate.doc.SiteConfig
---@param locale string
---@return hecate.doc.TopLink[]
function M.top_links(pages, config, locale)
  local by_id = {}
  for _, page in ipairs(pages) do by_id[page.id] = page end
  local links = {}
  if config.nav then
    for _, entry in ipairs(config.nav) do
      local text = config_module.localise(entry.text, locale, config.default_locale)
      if entry.link:find("^%a[%w+.%-]*:") then
        links[#links + 1] = { text = text or entry.link, url = entry.link }
      else
        local path = entry.link:gsub("/+$", "")
        local target = by_id[path] and path or (by_id[path .. "/index"] and path .. "/index") or nil
        if not target then
          -- link to the first page of the section
          local ids = {}
          for id in pairs(by_id) do
            if id:sub(1, #path + 1) == path .. "/" then ids[#ids + 1] = id end
          end
          table.sort(ids)
          target = ids[1]
        end
        if target then
          links[#links + 1] = {
            text = text or by_id[target].title, id = target, section = M.section_of(target) or target,
          }
        end
      end
    end
    return links
  end
  local sections, seen = {}, {}
  for _, page in ipairs(pages) do
    local section = M.section_of(page.id)
    if section and not seen[section] then
      seen[section] = true
      sections[#sections + 1] = section
    end
  end
  table.sort(sections)
  for _, section in ipairs(sections) do
    local index = by_id[section .. "/index"]
    local target = index
    if not target then
      local ids = {}
      for id in pairs(by_id) do
        if id:sub(1, #section + 1) == section .. "/" then ids[#ids + 1] = id end
      end
      table.sort(ids)
      target = by_id[ids[1]]
    end
    links[#links + 1] = { text = index and index.title or humanise(section), id = target.id, section = section }
  end
  return links
end

return M
