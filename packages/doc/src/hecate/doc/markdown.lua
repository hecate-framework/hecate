-- Markdown renderer: the CommonMark 0.31 subset that documentation needs, plus the GFM
-- tables, task lists and strikethrough extensions and `::: tip` style containers.
--
-- Supported blocks (CommonMark sections): thematic breaks 4.1, ATX headings 4.2, setext
-- headings 4.3, indented code 4.4, fenced code 4.5, link reference definitions 4.7
-- (single line), paragraphs 4.8, block quotes 5.1, list items and lists 5.2 and 5.3
-- (tight and loose), GFM tables (spec 0.29 section 4.10) and task list items (5.3).
-- Inline constructs live in hecate.doc.internal.inline.
--
-- Raw HTML is not supported: it is escaped and shown as text (HTML comments are dropped,
-- so generated pages can carry their "generated, do not edit" header). Together with the
-- URL allow-list this makes the output safe by default for untrusted content.
-- Deliberate simplifications (recorded in packages/doc/README.md): no lazy continuation
-- inside nested quotes of lists, no multi-line link reference definitions, no entity
-- table beyond the numeric and the five XML entities.
global <const> string, table, ipairs, require, tostring, tonumber, math, assert

local html = require("hecate.doc.internal.html")
local inline = require("hecate.doc.internal.inline")
local highlight = require("hecate.doc.highlight")

local escape = html.escape

local M = {}

---@class hecate.doc.MarkdownOptions
---@field labels? table<string, string>  titles of the containers: note, tip, warning, danger
---@field resolve_link? fun(href: string): string  rewrites link destinations and image sources
---@field highlight? boolean  highlight fenced code (default true)
---@field strip_title? boolean  remove a leading level-1 heading and return its text as `title`
---@field heading_anchors? boolean  add a permalink to headings (default true)

---@class hecate.doc.Heading
---@field level integer
---@field id string
---@field text string  plain text

---@class hecate.doc.Section
---@field id? string  identifier of the heading that opens the section (nil before the first)
---@field heading? string
---@field level? integer
---@field text string  plain text of the section body

---@class hecate.doc.RenderResult
---@field html string
---@field title? string  set when `strip_title` removed a leading level-1 heading
---@field headings hecate.doc.Heading[]
---@field sections hecate.doc.Section[]
---@field links string[]  every link destination met, as written

local DEFAULT_LABELS = { note = "Note", tip = "Tip", warning = "Warning", danger = "Danger" }

local function is_blank(line) return line:match("^%s*$") ~= nil end

local function indent_of(line) return #(line:match("^ *") or "") end

--- Expands the tabs of the indentation and of the space after a list marker to spaces, with
--- tab stops every four columns (CommonMark 2.2); tabs elsewhere are left alone.
local function expand_tabs(line)
  local function expand(text, column)
    local out = {}
    for char in text:gmatch(".") do
      if char == "\t" then
        local width = 4 - column % 4
        out[#out + 1] = (" "):rep(width)
        column = column + width
      else
        out[#out + 1] = char
        column = column + 1
      end
    end
    return table.concat(out), column
  end
  local indent = line:match("^[ \t]*")
  local expanded, column = expand(indent, 0)
  local rest = line:sub(#indent + 1)
  local marker, gap = rest:match("^([-+*])([ \t]+)")
  if not marker then marker, gap = rest:match("^(%d+[.)])([ \t]+)") end
  if marker and gap:find("\t", 1, true) then
    local spaces = expand(gap, column + #marker)
    rest = marker .. spaces .. rest:sub(#marker + #gap + 1)
  end
  return expanded .. rest
end

local function split_lines(source)
  source = source:gsub("^\xEF\xBB\xBF", ""):gsub("\r\n?", "\n")
  local lines = {}
  for text in (source .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = expand_tabs(text) end
  while #lines > 0 and lines[#lines] == "" do lines[#lines] = nil end
  return lines
end

-- Block starts ------------------------------------------------------------------------

--- Recognises an opening code fence; returns indent, fence character, length, info.
local function fence_open(line)
  local indent, run, info = line:match("^( *)(`+)(.*)$")
  local char = "`"
  if not run or #run < 3 then
    indent, run, info = line:match("^( *)(~+)(.*)$")
    char = "~"
  end
  if not run or #run < 3 or #indent > 3 then return nil end
  info = info:match("^%s*(.-)%s*$")
  if char == "`" and info:find("`", 1, true) then return nil end
  return #indent, char, #run, info
end

local function atx_heading(line)
  local hashes, rest = line:match("^ ? ? ?(#+)(.*)$")
  if not hashes or #hashes > 6 then return nil end
  if rest ~= "" and not rest:match("^[ \t]") then return nil end
  rest = rest:match("^%s*(.-)%s*$"):gsub("%s+#+$", ""):gsub("^#+$", "")
  return #hashes, rest
end

local function is_thematic_break(line)
  local stripped = line:match("^ ? ? ?(.-)%s*$")
  if stripped == nil or #line - #(line:match("^ *")) > #stripped + 3 then return false end
  local char = stripped:sub(1, 1)
  if char ~= "-" and char ~= "*" and char ~= "_" then return false end
  local count = 0
  for c in stripped:gmatch("%S") do
    if c ~= char then return false end
    count = count + 1
  end
  return count >= 3 and indent_of(line) <= 3
end

---@class hecate.doc.ListMarker
---@field ordered boolean
---@field indent integer
---@field marker string  bullet character or ordered delimiter
---@field number integer
---@field width integer  column where the item content starts
---@field rest string  content of the first line

local function list_marker(line)
  local indent, marker, spaces, rest = line:match("^( *)([-+*])( +)(.*)$")
  local ordered, number, raw = false, 1, marker
  if not marker then
    indent, marker, spaces = line:match("^( *)([-+*])()$")
    if marker then rest, spaces, raw = "", " ", marker end
  end
  if not marker then
    local digits, delimiter
    indent, digits, delimiter, spaces, rest = line:match("^( *)(%d+)([.)])( +)(.*)$")
    if not digits then
      indent, digits, delimiter = line:match("^( *)(%d+)([.)])$")
      if digits then rest, spaces = "", " " end
    end
    if not digits or #digits > 9 then return nil end
    ordered, number, marker, raw = true, math.tointeger(tonumber(digits)) or 1, delimiter, digits .. delimiter
  end
  if #indent > 3 then return nil end
  local gap = #spaces
  if gap > 4 and rest ~= "" then
    -- more than four spaces after the marker: the content is an indented code block.
    rest = (" "):rep(gap - 1) .. rest
    gap = 1
  end
  return {
    ordered = ordered, indent = #indent, marker = marker, number = number,
    width = #indent + #raw + gap, rest = rest,
  }
end

local function container_open(line)
  local colons, name, title = line:match("^(:::+)%s*([%a][%w%-]*)%s*(.-)%s*$")
  if not colons or indent_of(line) > 0 then return nil end
  return #colons, name, title
end

local function container_close(line)
  local colons = line:match("^(:::+)%s*$")
  return colons and #colons or nil
end

local CONTAINERS = { note = true, tip = true, warning = true, danger = true }

local function interrupts_paragraph(line)
  if fence_open(line) or atx_heading(line) or is_thematic_break(line) then return true end
  if line:match("^ ? ? ?>") or line:match("^%s*<!%-%-") then return true end
  local colons, name = container_open(line)
  if colons and CONTAINERS[name] then return true end
  local marker = list_marker(line)
  if marker and marker.rest ~= "" and (not marker.ordered or marker.number == 1) then return true end
  return false
end

-- Tables ------------------------------------------------------------------------------

local function split_row(line)
  line = line:match("^%s*(.-)%s*$")
  if line:sub(1, 1) == "|" then line = line:sub(2) end
  if line:sub(-1) == "|" and line:sub(-2, -2) ~= "\\" then line = line:sub(1, -2) end
  local cells, buffer, i = {}, {}, 1
  while i <= #line do
    local char = line:sub(i, i)
    if char == "\\" and line:sub(i + 1, i + 1) == "|" then
      buffer[#buffer + 1] = "|"
      i = i + 2
    elseif char == "|" then
      cells[#cells + 1] = table.concat(buffer)
      buffer = {}
      i = i + 1
    else
      buffer[#buffer + 1] = char
      i = i + 1
    end
  end
  cells[#cells + 1] = table.concat(buffer)
  for index, cell in ipairs(cells) do cells[index] = cell:match("^%s*(.-)%s*$") end
  return cells
end

--- Returns the alignments of a delimiter row, or nil when the line is not one.
local function delimiter_row(line)
  if not line:find("-", 1, true) or not line:find("^[%s|:%-]+$") then return nil end
  local aligns = {}
  for _, cell in ipairs(split_row(line)) do
    local left, right = cell:match("^(:?)%-+(:?)$")
    if not left then return nil end
    aligns[#aligns + 1] = (left ~= "" and right ~= "") and "center" or (right ~= "" and "right")
      or (left ~= "" and "left") or false
  end
  return aligns
end

-- Rendering ---------------------------------------------------------------------------

local blocks -- forward declaration

local function render_inline(text, ctx) return inline.render(text, ctx.inline) end

local function unique_id(ctx, text, custom)
  local base = custom or html.slug(text)
  local id, suffix = base, 0
  while ctx.ids[id] do
    suffix = suffix + 1
    id = base .. "-" .. suffix
  end
  ctx.ids[id] = true
  return id
end

local function render_heading(ctx, level, text)
  local custom
  local stripped, id_text = text:match("^(.-)%s*{#([%w_%-%.:]+)}$")
  if stripped then text, custom = stripped, id_text end
  local plain = inline.plain(text)
  local id = unique_id(ctx, plain, custom)
  ctx.headings[#ctx.headings + 1] = { level = level, id = id, text = plain }
  local anchor = ""
  if ctx.options.heading_anchors ~= false then
    anchor = ("<a class=\"header-anchor\" href=\"#%s\" aria-label=\"Permalink to “%s”\"></a>"):format(
      escape(id), escape(plain))
  end
  local rendered = ("<h%d id=\"%s\" tabindex=\"-1\">%s%s</h%d>"):format(level, escape(id),
    render_inline(text, ctx), anchor, level)
  return rendered, { level = level, id = id, text = plain }
end

local function render_code(ctx, info, code)
  local language = info:match("^([^%s{]+)") or ""
  local safe_language = language:match("^[%w_+#.%-]+$") and language or ""
  local body
  if ctx.options.highlight == false then body = escape(code) else body = highlight.render(safe_language, code) end
  local label = safe_language ~= "" and ("<span class=\"code-language\">%s</span>"):format(
    escape(highlight.label(safe_language))) or ""
  return ("<div class=\"code-block\"%s><div class=\"code-toolbar\">%s</div><pre tabindex=\"0\"><code%s>%s</code></pre></div>"):format(
    safe_language ~= "" and (" data-language=\"" .. escape(safe_language:lower()) .. "\"") or "",
    label, safe_language ~= "" and (" class=\"language-" .. escape(safe_language:lower()) .. "\"") or "", body)
end

local function render_table(ctx, header, aligns, rows)
  local function cell(tag, text, index)
    local align = aligns[index]
    return ("<%s%s%s>%s</%s>"):format(tag, tag == "th" and " scope=\"col\"" or "",
      align and (" class=\"align-" .. align .. "\"") or "", render_inline(text, ctx), tag)
  end
  local head = {}
  for index = 1, #aligns do head[index] = cell("th", header[index] or "", index) end
  local body = {}
  for _, row in ipairs(rows) do
    local cells = {}
    for index = 1, #aligns do cells[index] = cell("td", row[index] or "", index) end
    body[#body + 1] = "<tr>" .. table.concat(cells) .. "</tr>"
  end
  return "<div class=\"table-wrap\"><table><thead><tr>" .. table.concat(head)
    .. "</tr></thead>" .. (#body > 0 and ("<tbody>" .. table.concat(body, "\n") .. "</tbody>") or "")
    .. "</table></div>"
end

local function join(items)
  local parts = {}
  for _, item in ipairs(items) do parts[#parts + 1] = item.html end
  return table.concat(parts, "\n")
end

--- Parses a list starting at lines[i]; returns the HTML and the index after the list.
local function parse_list(lines, i, ctx)
  local first = assert(list_marker(lines[i]))
  local n = #lines
  local items, loose = {}, false
  while i <= n do
    local marker = list_marker(lines[i])
    if not marker or marker.ordered ~= first.ordered or marker.marker ~= first.marker
      or is_thematic_break(lines[i]) then
      break
    end
    local width = marker.width
    local content = { marker.rest }
    local j = i + 1
    while j <= n do
      local line = lines[j]
      if is_blank(line) then
        local k = j
        while k <= n and is_blank(lines[k]) do k = k + 1 end
        if k > n or indent_of(lines[k]) < width then break end
        for _ = j, k - 1 do content[#content + 1] = "" end
        j = k
      elseif indent_of(line) >= width then
        content[#content + 1] = line:sub(width + 1)
        j = j + 1
      elseif content[#content] ~= "" and not interrupts_paragraph(line) and not list_marker(line)
        and not fence_open(content[#content]) then
        content[#content + 1] = line:gsub("^ +", "")
        j = j + 1
      else
        break
      end
    end
    -- A blank line between two blocks directly inside the item makes the list loose.
    local in_fence = false
    for index, line in ipairs(content) do
      if fence_open(line) then in_fence = not in_fence end
      if line == "" and not in_fence and index < #content and indent_of(content[index + 1]) == 0 then
        loose = true
      end
    end
    items[#items + 1] = content
    i = j
    local k = i
    while k <= n and is_blank(lines[k]) do k = k + 1 end
    local sibling = k <= n and list_marker(lines[k]) or nil
    if sibling and sibling.ordered == first.ordered and sibling.marker == first.marker
      and not is_thematic_break(lines[k]) then
      if k > i then loose = true end
      i = k
    else
      break
    end
  end
  local out, has_task = {}, false
  for _, content in ipairs(items) do
    local task, checked
    local mark, text = content[1]:match("^%[([ xX])%]%s+(.*)$")
    if mark then
      task, checked = true, mark ~= " "
      content[1] = text
      has_task = true
    end
    local body = join(blocks(content, ctx, not loose))
    if task then
      local box = ("<input type=\"checkbox\" disabled%s> "):format(checked and " checked" or "")
      if body:sub(1, 3) == "<p>" then body = "<p>" .. box .. body:sub(4) else body = box .. body end
    end
    out[#out + 1] = ("<li%s>%s</li>"):format(task and " class=\"task-list-item\"" or "", body)
  end
  local tag = first.ordered and "ol" or "ul"
  local attributes = ""
  if first.ordered and first.number ~= 1 then attributes = (" start=\"%d\""):format(first.number) end
  if has_task then attributes = attributes .. " class=\"contains-task-list\"" end
  return ("<%s%s>\n%s\n</%s>"):format(tag, attributes, table.concat(out, "\n"), tag), i
end

--- Parses block-level structure. `tight` renders paragraphs without `<p>` (tight lists).
---@return { html: string, heading?: table }[]
function blocks(lines, ctx, tight)
  local out = {}
  local function add(rendered, heading) out[#out + 1] = { html = rendered, heading = heading } end
  local i, n = 1, #lines
  while i <= n do
    local line = lines[i]
    local fence_indent, fence_char, fence_length, info = fence_open(line)
    local level, heading_text = atx_heading(line)
    local colons, container_name, container_title = container_open(line)
    local marker = list_marker(line)
    if is_blank(line) then
      i = i + 1
    elseif line:match("^%s*<!%-%-") then
      -- HTML comment: dropped, up to the line that closes it.
      while i <= n and not lines[i]:find("%-%->") do i = i + 1 end
      i = i + 1
    elseif fence_char then
      local content, closed = {}, false
      i = i + 1
      while i <= n do
        local close = lines[i]:match("^ ? ? ?(" .. (fence_char == "`" and "`+" or "~+") .. ")%s*$")
        if close and #close >= fence_length then
          closed = true
          i = i + 1
          break
        end
        local text = lines[i]
        local strip = math.min(fence_indent or 0, indent_of(text))
        content[#content + 1] = text:sub(strip + 1)
        i = i + 1
      end
      add(render_code(ctx, info, table.concat(content, "\n")))
      if not closed then i = n + 1 end
    elseif level then
      local rendered, heading = render_heading(ctx, level, heading_text)
      add(rendered, heading)
      i = i + 1
    elseif is_thematic_break(line) then
      add("<hr>")
      i = i + 1
    elseif colons and CONTAINERS[container_name] then
      local content, depth = {}, 1
      local in_fence
      i = i + 1
      while i <= n do
        local current = lines[i]
        local _, fchar, flength = fence_open(current)
        if fchar then
          if not in_fence then in_fence = { fchar, flength }
          elseif in_fence[1] == fchar and flength >= in_fence[2] and current:match("^ *[`~]+%s*$") then
            in_fence = nil
          end
        elseif not in_fence then
          local close = container_close(current)
          local open = container_open(current)
          if close and close >= colons then
            depth = depth - 1
            if depth == 0 then break end
          elseif open and open == colons then
            depth = depth + 1
          end
        end
        content[#content + 1] = current
        i = i + 1
      end
      i = i + 1
      local labels = ctx.options.labels or DEFAULT_LABELS
      local title = container_title ~= "" and container_title or labels[container_name]
        or DEFAULT_LABELS[container_name]
      add(("<div class=\"callout callout-%s\" role=\"note\">\n<p class=\"callout-title\">%s</p>\n%s\n</div>")
        :format(container_name, render_inline(title, ctx), join(blocks(content, ctx, false))))
    elseif line:match("^ ? ? ?>") then
      local content = {}
      while i <= n do
        local current = lines[i]
        if current:match("^ ? ? ?>") then
          content[#content + 1] = current:gsub("^ ? ? ?> ?", "")
        elseif not is_blank(current) and #content > 0 and not is_blank(content[#content])
          and not interrupts_paragraph(current) and not fence_open(content[#content]) then
          content[#content + 1] = current
        else
          break
        end
        i = i + 1
      end
      add("<blockquote>\n" .. join(blocks(content, ctx, false)) .. "\n</blockquote>")
    elseif marker then
      local rendered
      rendered, i = parse_list(lines, i, ctx)
      add(rendered)
    elseif indent_of(line) >= 4 then
      local content = {}
      while i <= n and (indent_of(lines[i]) >= 4 or is_blank(lines[i])) do
        content[#content + 1] = lines[i]:sub(5)
        i = i + 1
      end
      while content[#content] == "" do content[#content] = nil end
      add(render_code(ctx, "", table.concat(content, "\n")))
    elseif line:find("|", 1, true) and lines[i + 1] and delimiter_row(lines[i + 1])
      and #split_row(line) == #delimiter_row(lines[i + 1]) then
      local aligns = delimiter_row(lines[i + 1])
      local header = split_row(line)
      local rows = {}
      i = i + 2
      while i <= n and not is_blank(lines[i]) and not fence_open(lines[i]) and not atx_heading(lines[i])
        and not lines[i]:match("^ ? ? ?>") do
        rows[#rows + 1] = split_row(lines[i])
        i = i + 1
      end
      add(render_table(ctx, header, aligns, rows))
    else
      local text = { (line:gsub("^ +", "")) }
      local setext
      i = i + 1
      while i <= n do
        local current = lines[i]
        if is_blank(current) then break end
        local underline = current:match("^ ? ? ?(=+)%s*$") and 1 or (current:match("^ ? ? ?(%-+)%s*$") and 2)
        if underline then
          setext = underline
          i = i + 1
          break
        end
        if interrupts_paragraph(current) then break end
        text[#text + 1] = current:gsub("^ +", "")
        i = i + 1
      end
      local joined = table.concat(text, "\n")
      if setext then
        local rendered, heading = render_heading(ctx, setext, (joined:gsub("\n", " ")))
        add(rendered, heading)
      elseif tight then
        add(render_inline(joined, ctx))
      else
        add("<p>" .. render_inline(joined, ctx) .. "</p>")
      end
    end
  end
  return out
end

--- Removes single-line link reference definitions (CommonMark 4.7) outside code fences
--- and returns the remaining lines and the definitions by normalised label.
local function extract_definitions(lines)
  local kept, refs = {}, {}
  local in_fence
  for _, line in ipairs(lines) do
    local _, char, length = fence_open(line)
    local consumed = false
    if char then
      if not in_fence then in_fence = { char, length }
      elseif in_fence[1] == char and length >= in_fence[2] and line:match("^ *[`~]+%s*$") then in_fence = nil end
    elseif not in_fence and indent_of(line) <= 3 then
      local label, rest = line:match("^ *%[([^%]]+)%]:%s*(.+)$")
      if label and not label:find("^%^") then
        local destination, tail = rest:match("^<([^<>]*)>%s*(.*)$")
        if not destination then destination, tail = rest:match("^(%S+)%s*(.*)$") end
        local title
        if tail and tail ~= "" then
          title = tail:match('^"(.*)"$') or tail:match("^'(.*)'$") or tail:match("^%((.*)%)$")
        end
        if destination and (tail == "" or title) then
          local key = inline.normalise_label(label)
          if not refs[key] then refs[key] = { href = destination, title = title } end
          consumed = true
        end
      end
    end
    if not consumed then kept[#kept + 1] = line end
  end
  return kept, refs
end

--- Renders a Markdown body (front matter already removed).
---@param source string
---@param options? hecate.doc.MarkdownOptions
---@return hecate.doc.RenderResult
function M.render(source, options)
  options = options or {}
  local lines, refs = extract_definitions(split_lines(source))
  local links = {}
  local ctx = {
    options = options,
    ids = {},
    headings = {},
    inline = { refs = refs, resolve_link = options.resolve_link, links = links },
  }
  local top = blocks(lines, ctx, false)
  local title
  if options.strip_title and top[1] and top[1].heading and top[1].heading.level == 1 then
    title = top[1].heading.text
    table.remove(top, 1)
    table.remove(ctx.headings, 1)
  end
  local sections = { { text = "" } }
  for _, block in ipairs(top) do
    local current = sections[#sections]
    if block.heading and (block.heading.level == 2 or block.heading.level == 3) then
      sections[#sections + 1] = {
        id = block.heading.id, heading = block.heading.text, level = block.heading.level, text = "",
      }
    else
      local text = block.heading and block.heading.text or html.strip_tags(block.html)
      current.text = current.text .. " " .. text
    end
  end
  for _, section in ipairs(sections) do
    section.text = section.text:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
  end
  return { html = join(top), title = title, headings = ctx.headings, sections = sections, links = links }
end

return M
