-- Inline Markdown renderer: code spans, emphasis, strong, strikethrough, links, images,
-- autolinks, backslash escapes, entities and hard breaks. Follows CommonMark 0.31 sections
-- 6.1 (code spans), 6.2 (emphasis, the delimiter run algorithm and the "rule of 3"),
-- 6.3 (links), 6.4 (images), 6.5 (autolinks), 6.7 and 6.8 (breaks) for the supported
-- constructs. Raw inline HTML is not supported: it is escaped, so it renders as text
-- (HTML comments are dropped). Strikethrough with two tildes is a GFM extension.
global <const> string, table, type, ipairs, require

local html = require("hecate.doc.internal.html")

local escape = html.escape

local M = {}

local PUNCTUATION = "^%p$" -- ASCII punctuation (CommonMark 2.1), in the C locale

--- Normalises a link label for reference lookup (CommonMark 4.7): case-fold, collapse
--- whitespace.
---@param label string
---@return string
function M.normalise_label(label)
  return (html.lower(label):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

local function unescape_backslashes(text)
  return (text:gsub("\\(%p)", "%1"))
end

local function is_space(char) return char == "" or char:match("^%s$") ~= nil or char == "\1" end

--- Parses `(destination "title")` starting at `pos` (the opening parenthesis). Returns
--- the destination, the title or nil, and the position after the closing parenthesis.
---@return string? destination
---@return string? title
---@return integer? after
local function parse_link_tail(text, pos)
  if text:sub(pos, pos) ~= "(" then return nil end
  local p = text:match("^[ \n]*()", pos + 1)
  local destination
  if text:sub(p, p) == "<" then
    local inside, after = text:match("^<([^<>\n]*)>()", p)
    if not inside then return nil end
    destination, p = inside, after
  else
    local depth, q = 0, p
    while q <= #text do
      local char = text:sub(q, q)
      if char == "\\" then
        q = q + 2
      elseif char == "(" then
        depth, q = depth + 1, q + 1
      elseif char == ")" then
        if depth == 0 then break end
        depth, q = depth - 1, q + 1
      elseif char:match("[%s%c]") then
        break
      else
        q = q + 1
      end
    end
    destination, p = text:sub(p, q - 1), q
  end
  p = text:match("^[ \n]*()", p)
  local title
  local quote = text:sub(p, p)
  if quote == '"' or quote == "'" or quote == "(" then
    local close = quote == "(" and ")" or quote
    local q = p + 1
    while q <= #text do
      local char = text:sub(q, q)
      if char == "\\" then q = q + 2 elseif char == close then break else q = q + 1 end
    end
    if q > #text then return nil end
    title = unescape_backslashes(text:sub(p + 1, q - 1))
    p = text:match("^[ \n]*()", q + 1)
  end
  if text:sub(p, p) ~= ")" then return nil end
  return unescape_backslashes(destination), title, p + 1
end

--- Concatenates items a..b as HTML; unmatched delimiters and brackets become literals.
local function flatten(items, first, last)
  local out = {}
  for index = first, last do
    local item = items[index]
    if type(item) == "string" then
      out[#out + 1] = item
    elseif item.delim then
      out[#out + 1] = item.ch:rep(item.n)
    else
      out[#out + 1] = item.image and "![" or "["
    end
  end
  return table.concat(out)
end

--- Resolves emphasis among the delimiter items from index `from` (CommonMark 6.2,
--- "process emphasis"). Matched runs are replaced by one HTML string.
local function process_emphasis(items, from)
  local ci = from
  while ci <= #items do
    local closer = items[ci]
    if type(closer) == "table" and closer.delim and closer.close and closer.n > 0 then
      local oi
      for k = ci - 1, from, -1 do
        local o = items[k]
        if type(o) == "table" and o.delim and o.ch == closer.ch and o.open and o.n > 0 then
          local odd_match = (o.close or closer.open) and (o.orig + closer.orig) % 3 == 0
            and not (o.orig % 3 == 0 and closer.orig % 3 == 0)
          if closer.ch == "~" or not odd_match then
            oi = k
            break
          end
        end
      end
      if oi then
        local opener = items[oi]
        local use = closer.ch == "~" and 2 or ((opener.n >= 2 and closer.n >= 2) and 2 or 1)
        local tag = closer.ch == "~" and "del" or (use == 2 and "strong" or "em")
        local inner = flatten(items, oi + 1, ci - 1)
        for _ = oi + 1, ci - 1 do table.remove(items, oi + 1) end
        table.insert(items, oi + 1, ("<%s>%s</%s>"):format(tag, inner, tag))
        opener.n, closer.n = opener.n - use, closer.n - use
        ci = oi + 2
        if opener.n == 0 then
          table.remove(items, oi)
          ci = ci - 1
        end
        if closer.n == 0 then table.remove(items, ci) end
      else
        ci = ci + 1
      end
    else
      ci = ci + 1
    end
  end
end

---@class hecate.doc.InlineContext
---@field refs? table<string, { href: string, title?: string }>  link reference definitions
---@field resolve_link? fun(href: string): string  rewrites a destination (site links)
---@field links? string[]  receives every raw destination met (for link checking)

--- Renders inline Markdown to HTML.
---@param text string
---@param context? hecate.doc.InlineContext
---@return string
function M.render(text, context)
  context = context or {}
  text = text:gsub("[%z\1-\8\11\12\14-\31]", "")
  text = text:gsub("[ \t]+\n", function(spaces) return #spaces >= 2 and "\1\n" or "\n" end)
  text = text:gsub("\n[ \t]+", "\n"):gsub("[ \t]+$", "")
  local items, brackets = {}, {}
  local position, length = 1, #text

  local function push(item) items[#items + 1] = item end

  local function emit_link(opener, destination, title, inner)
    local href = destination
    if context.links then context.links[#context.links + 1] = destination end
    if context.resolve_link then href = context.resolve_link(href) end
    if opener.image then
      if not html.is_safe_url(href) then return escape(html.strip_tags(inner, "")) end
      return ("<img src=\"%s\" alt=\"%s\"%s loading=\"lazy\" decoding=\"async\">"):format(
        escape((href:gsub(" ", "%%20"))), escape(html.strip_tags(inner, "")),
        title and (" title=\"" .. escape(title) .. "\"") or "")
    end
    if not html.is_safe_url(href) then return inner end
    return ("<a href=\"%s\"%s>%s</a>"):format(escape((href:gsub(" ", "%%20"))),
      title and (" title=\"" .. escape(title) .. "\"") or "", inner)
  end

  while position <= length do
    local found = text:find("[\\`*_~%[%]!<&\1]", position)
    if not found then
      push(escape(text:sub(position)))
      break
    end
    if found > position then push(escape(text:sub(position, found - 1))) end
    position = found
    local char = text:sub(position, position)
    if char == "\\" then
      local next_char = text:sub(position + 1, position + 1)
      if next_char:match(PUNCTUATION) then
        push(escape(next_char))
        position = position + 2
      elseif next_char == "\n" then
        push("<br>")
        position = position + 1
      else
        push("\\")
        position = position + 1
      end
    elseif char == "\1" then
      push("<br>")
      position = position + 1
    elseif char == "`" then
      local run = text:match("^`+", position)
      local close_start, close_end
      local search = position + #run
      while true do
        local first, last = text:find("`+", search)
        if not first then break end
        if last - first + 1 == #run then
          close_start, close_end = first, last
          break
        end
        search = last + 1
      end
      if close_start then
        local code = text:sub(position + #run, close_start - 1):gsub("[\n\1]", " ")
        if code:match("^ .* $") and code:match("[^ ]") then code = code:sub(2, -2) end
        push("<code>" .. escape(code) .. "</code>")
        position = close_end + 1
      else
        push(run)
        position = position + #run
      end
    elseif char == "<" then
      local url = text:match("^<([%a][%w+.%-]*:[^%s<>]*)>", position)
      local mail = not url and text:match("^<([%w.!#$%%&'*+/=?^_`{|}~%-]+@[%w%-.]+)>", position)
      local comment = not url and not mail and text:match("^<!%-%-.-%-%->", position)
      if url then
        if context.links then context.links[#context.links + 1] = url end
        if html.is_safe_url(url) then
          push(("<a href=\"%s\">%s</a>"):format(escape(url), escape(url)))
        else
          push(escape(url))
        end
        position = position + #url + 2
      elseif mail then
        push(("<a href=\"mailto:%s\">%s</a>"):format(escape(mail), escape(mail)))
        position = position + #mail + 2
      elseif comment then
        position = position + #comment
      else
        push("&lt;")
        position = position + 1
      end
    elseif char == "&" then
      local entity = text:match("^&#?%w+;", position)
      if entity then
        push(entity)
        position = position + #entity
      else
        push("&amp;")
        position = position + 1
      end
    elseif char == "*" or char == "_" or char == "~" then
      local run = text:match("^" .. (char == "*" and "%*" or char) .. "+", position)
      local before = position > 1 and text:sub(position - 1, position - 1) or ""
      local after = text:sub(position + #run, position + #run)
      if char == "~" and #run ~= 2 then
        push(run)
      else
        local before_space, after_space = is_space(before), is_space(after)
        local before_punct, after_punct = before:match(PUNCTUATION) ~= nil, after:match(PUNCTUATION) ~= nil
        local left = not after_space and (not after_punct or before_space or before_punct)
        local right = not before_space and (not before_punct or after_space or after_punct)
        local open, close = left, right
        if char == "_" then
          open = left and (not right or before_punct)
          close = right and (not left or after_punct)
        end
        push({ delim = true, ch = char, n = #run, orig = #run, open = open, close = close })
      end
      position = position + #run
    elseif char == "!" then
      if text:sub(position + 1, position + 1) == "[" then
        local opener = { bracket = true, image = true, active = true, pos = #items + 1, start = position + 2 }
        push(opener)
        brackets[#brackets + 1] = opener
        position = position + 2
      else
        push("!")
        position = position + 1
      end
    elseif char == "[" then
      local opener = { bracket = true, image = false, active = true, pos = #items + 1, start = position + 1 }
      push(opener)
      brackets[#brackets + 1] = opener
      position = position + 1
    else -- "]"
      local opener = brackets[#brackets]
      if opener and not opener.active then
        brackets[#brackets] = nil
        opener = nil
      end
      local destination, title, after
      if opener then
        destination, title, after = parse_link_tail(text, position + 1)
        if not destination then
          local label = text:sub(opener.start, position - 1)
          local reference_label, reference_end
          if text:sub(position + 1, position + 1) == "[" then
            local inside, finish = text:match("^%[([^%[%]]*)%]()", position + 1)
            if inside then
              reference_label = inside ~= "" and inside or label
              reference_end = finish
            end
          else
            reference_label, reference_end = label, position + 1
          end
          local reference = reference_label and context.refs
            and context.refs[M.normalise_label(reference_label)]
          if reference then
            destination, title, after = reference.href, reference.title, reference_end
          end
        end
      end
      if opener and destination then
        process_emphasis(items, opener.pos + 1)
        local inner = flatten(items, opener.pos + 1, #items)
        for k = #items, opener.pos, -1 do items[k] = nil end
        brackets[#brackets] = nil
        push(emit_link(opener, destination, title, inner))
        if not opener.image then
          for _, other in ipairs(brackets) do
            if not other.image then other.active = false end
          end
        end
        position = after
      else
        if opener then brackets[#brackets] = nil end
        push("]")
        position = position + 1
      end
    end
  end
  process_emphasis(items, 1)
  return flatten(items, 1, #items)
end

--- Returns the plain text of inline Markdown (used for heading text and search).
---@param text string
---@return string
function M.plain(text)
  return (html.strip_tags(M.render(text), ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

return M
