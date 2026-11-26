-- Editing `hecate.project.lua` as text (ADR 0009: the manifest is Lua that people write and comment): add, replace or
-- remove one dependency, leaving every other byte as it was. Two rules keep it safe: it refuses when the file is not in
-- a shape it understands (the error carries the line to write by hand), and it checks its own result by evaluating
-- the new text and comparing the table with the one expected.
global <const> require, type, ipairs, pairs, pcall, table, error, tostring, next

local core = require("hecate.core")
local lua_text = require("hecate.cli.internal.lua_text")
local tokens_module = require("hecate.cli.internal.lua_tokens")
local manifest_module = require("hecate.cli.manifest")

--- Editing the dependency tables of a manifest.
---@class hecate.cli.manifest_edit
local M = {}

--- The sections an edit may target.
M.SECTIONS = { "dependencies", "development_dependencies" }

---@class hecate.cli.EditError : hecate.core.Error

---@param reason string
---@param line_to_write string
---@param section string
local function refuse(reason, line_to_write, section)
  error(core.ConfigurationError({
    message = "hecate.project.lua: cannot edit it safely (" .. reason .. "). Add this line to the `" .. section
      .. "` table yourself:\n  " .. line_to_write,
    context = { reason = reason, line = line_to_write, section = section },
  }), 0)
end

local function entry_line(name, constraint)
  return "[" .. lua_text.quote(name) .. "] = " .. lua_text.quote(constraint) .. ","
end

--- Where everything is: tokens, line numbers, the returned table, its sections and their entries.
local function analyse(text, line_to_write, section)
  local all, message = tokens_module.tokenize(text)
  if not all then refuse(message or "unreadable", line_to_write, section) end
  all = all --[[@as hecate.cli.Token[] ]]
  local tokens = tokens_module.significant(all)

  local line_starts = { 1 }
  for position in text:gmatch("()\n") do line_starts[#line_starts + 1] = position + 1 end
  local function line_of(position)
    local low, high = 1, #line_starts
    while low < high do
      local middle = (low + high + 1) // 2
      if line_starts[middle] <= position then low = middle else high = middle - 1 end
    end
    return low
  end

  -- The table after `return`.
  local first = tokens[1]
  if not (first and first.text == "return" and tokens[2] and tokens[2].text == "{") then
    refuse("the file does not start with `return {`", line_to_write, section)
  end
  local function closing(open_index)
    local depth = 0
    for index = open_index, #tokens do
      local text_of = tokens[index].kind == "symbol" and tokens[index].text or nil
      if text_of == "{" then depth = depth + 1 elseif text_of == "}" then
        depth = depth - 1
        if depth == 0 then return index end
      end
    end
    return nil
  end
  local top_close = closing(2) --[[@as integer]]
  if not top_close then refuse("the returned table is never closed", line_to_write, section) end

  local info = { text = text, tokens = tokens, line_of = line_of, line_starts = line_starts, top_open = 2, top_close = top_close, sections = {} }

  -- The members of a table, at its own depth: the index of the first and last token of each, and the comma after it.
  local function members(open_index, close_index)
    local list, depth, start = {}, 0, nil
    for index = open_index + 1, close_index - 1 do
      local token = tokens[index]
      local symbol = token.kind == "symbol" and token.text or nil
      if depth == 0 and (symbol == "," or symbol == ";") then
        if start then list[#list + 1] = { first = start, last = index - 1, comma = index }; start = nil end
      else
        start = start or index
        if symbol == "{" then depth = depth + 1 elseif symbol == "}" then depth = depth - 1 end
      end
    end
    if start then list[#list + 1] = { first = start, last = close_index - 1 } end
    return list
  end
  info.members = members

  for _, member in ipairs(members(2, top_close)) do
    local key, equals, brace = tokens[member.first], tokens[member.first + 1], tokens[member.first + 2]
    if key.kind == "name" and equals and equals.text == "=" and brace and brace.text == "{" then
      local close = closing(member.first + 2)
      if close == member.last then
        info.sections[key.text] = info.sections[key.text] or {}
        local list = info.sections[key.text]
        list[#list + 1] = { open = member.first + 2, close = close, entries = members(member.first + 2, close) }
      end
    end
  end
  return info
end

--- The entry of `name` in a section: the key may be `["name"]` or a bare name; the value a string.
local function find_entry(info, section, name)
  for _, entry in ipairs(section.entries) do
    local tokens = info.tokens
    local a, b, c, d, e = tokens[entry.first], tokens[entry.first + 1], tokens[entry.first + 2], tokens[entry.first + 3], tokens[entry.first + 4]
    local key, value
    if a.text == "[" and b and b.kind == "string" and c and c.text == "]" and d and d.text == "=" and e and e.kind == "string" and entry.last == entry.first + 4 then
      key, value = b.value, e
    elseif a.kind == "name" and b and b.text == "=" and c and c.kind == "string" and entry.last == entry.first + 2 then
      key, value = a.text, c
    end
    if key == name then return entry, value end
  end
  return nil
end

--- Whether the tokens `first` to `last` are alone on their lines (nothing but a comma and comments around them).
local function alone_on_lines(info, first, last, comma)
  local first_line, last_line = info.line_of(info.tokens[first].start), info.line_of(info.tokens[last].stop)
  for index, token in ipairs(info.tokens) do
    if index < first or index > (comma or last) then
      local line = info.line_of(token.start)
      if line >= first_line and line <= last_line then
        if not (index == comma) then return false end
      end
    end
  end
  return true
end

local function indentation_of_line(info, line)
  return info.text:match("^[ \t]*", info.line_starts[line]) or ""
end

--- Applies edits `{ start, stop, text }` (replace bytes `start..stop`, `stop = start - 1` inserts) from the end of the
--- file to the start, so positions stay valid.
local function apply(text, edits)
  -- A file with Windows line ends keeps them: the inserted lines get the same.
  local crlf = text:find("\r\n", 1, true) ~= nil
  table.sort(edits, function(a, b) return a.start > b.start end)
  for _, edit in ipairs(edits) do
    local inserted = crlf and edit.text:gsub("\r?\n", "\r\n") or edit.text
    text = text:sub(1, edit.start - 1) .. inserted .. text:sub(edit.stop + 1)
  end
  return text
end

--- A copy of the evaluated manifest with the change the edit asked for, to compare the result of the text edit with.
local function expected_table(before, section, name, constraint)
  local copy = {}
  for key, value in pairs(before) do
    if type(value) == "table" then
      local inner = {}
      for k, v in pairs(value) do inner[k] = v end
      copy[key] = inner
    else
      copy[key] = value
    end
  end
  if constraint ~= nil then
    copy[section] = copy[section] or {}
    copy[section][name] = constraint
  elseif copy[section] then
    copy[section][name] = nil
  end
  return copy
end

local function same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for key, value in pairs(a) do
    if not same(value, b[key]) then return false end
  end
  for key in pairs(b) do
    if a[key] == nil then return false end
  end
  return true
end

--- Checks the new text: it must evaluate to the old table plus the intended change, and nothing else.
local function verify(old_text, new_text, section, name, constraint, line_to_write)
  local ok_before, before = pcall(manifest_module.parse, old_text)
  if not ok_before then refuse("the manifest does not evaluate: " .. tostring((before --[[@as hecate.core.Error]]).message), line_to_write, section) end
  local ok, after = pcall(manifest_module.parse, new_text)
  if not ok then refuse("the edited text would not evaluate", line_to_write, section) end
  -- An emptied section is the same as an absent one.
  local expected = expected_table(before, section, name, constraint)
  if expected[section] and next(expected[section]) == nil then expected[section] = nil end
  if after[section] and next(after[section]) == nil then after[section] = nil end
  if not same(expected, after) then refuse("the edit did not give the expected result", line_to_write, section) end
end

--- The text of the manifest with `name` in `section` set to `constraint` (added, or its constraint replaced). Raises
--- `hecate.core.ConfigurationError` carrying the line to write by hand when the file is not in a shape this can edit
--- safely.
---@param text string
---@param section "dependencies"|"development_dependencies"
---@param name string
---@param constraint string
---@return string text
function M.set(text, section, name, constraint)
  local line_to_write = entry_line(name, constraint)
  local info = analyse(text, line_to_write, section)
  local found = info.sections[section]
  if found and #found > 1 then refuse("the table `" .. section .. "` appears more than once", line_to_write, section) end

  local edits = {}
  if found then
    local target = found[1]
    local entry, value = find_entry(info, target, name)
    if entry then
      if not alone_on_lines(info, entry.first, entry.last, entry.comma) then refuse("the entry is not alone on its line", line_to_write, section) end
      local literal = value --[[@as hecate.cli.Token]]
      edits[1] = { start = literal.start, stop = literal.stop, text = lua_text.quote(constraint) }
    else
      local open, close = info.tokens[target.open], info.tokens[target.close]
      local open_line, close_line = info.line_of(open.start), info.line_of(close.start)
      if #target.entries == 0 then
        local indent = indentation_of_line(info, open_line)
        if open_line ~= close_line then
          -- An empty table over several lines (it may hold comments): the new line goes before the closing brace.
          local close_indent = indentation_of_line(info, close_line)
          edits[1] = { start = info.line_starts[close_line], stop = info.line_starts[close_line] - 1, text = close_indent .. "  " .. line_to_write .. "\n" }
        else
          -- On one line, nothing but spaces may stand between the braces: a comment there would be lost.
          if text:sub(open.stop + 1, close.start - 1):find("%S") then refuse("a comment stands inside the braces", line_to_write, section) end
          edits[1] = { start = open.start, stop = close.stop, text = "{\n" .. indent .. "  " .. line_to_write .. "\n" .. indent .. "}" }
        end
      else
        local last = target.entries[#target.entries]
        local last_token = info.tokens[last.last]
        if open_line == close_line or info.line_of(last_token.stop) == close_line then
          refuse("the table is on one line", line_to_write, section)
        end
        if not alone_on_lines(info, last.first, last.last, last.comma) then refuse("an entry shares its line", line_to_write, section) end
        local indent = indentation_of_line(info, info.line_of(info.tokens[last.first].start))
        if not last.comma then edits[#edits + 1] = { start = last_token.stop + 1, stop = last_token.stop, text = "," } end
        edits[#edits + 1] = { start = info.line_starts[close_line], stop = info.line_starts[close_line] - 1, text = indent .. line_to_write .. "\n" }
      end
    end
  else
    local close = info.tokens[info.top_close]
    local close_line = info.line_of(close.start)
    local previous = info.tokens[info.top_close - 1]
    local top_members = info.members(info.top_open, info.top_close)
    if info.line_of(previous.stop) == close_line or info.line_of(info.tokens[info.top_open].start) == close_line then
      refuse("the table is on one line", line_to_write, section)
    end
    local indent = "  "
    if #top_members > 0 then indent = indentation_of_line(info, info.line_of(info.tokens[top_members[#top_members].first].start)) end
    if previous.text ~= "," and previous.text ~= "{" then
      edits[#edits + 1] = { start = previous.stop + 1, stop = previous.stop, text = "," }
    end
    local block = indent .. section .. " = {\n" .. indent .. "  " .. line_to_write .. "\n" .. indent .. "},\n"
    edits[#edits + 1] = { start = info.line_starts[close_line], stop = info.line_starts[close_line] - 1, text = block }
  end
  local result = apply(text, edits)
  verify(text, result, section, name, constraint, line_to_write)
  return result
end

--- The text of the manifest without the entry of `name` in `section`. The entry must be alone on its line. Raises
--- `hecate.core.ConfigurationError` when it is not in the table, or the file cannot be edited safely.
---@param text string
---@param section "dependencies"|"development_dependencies"
---@param name string
---@return string text
function M.remove(text, section, name)
  local line_to_write = "(remove the line of " .. lua_text.quote(name) .. ")"
  local info = analyse(text, line_to_write, section)
  local found = info.sections[section]
  if not found then refuse("there is no `" .. section .. "` table", line_to_write, section) end
  if #found > 1 then refuse("the table `" .. section .. "` appears more than once", line_to_write, section) end
  local entry = find_entry(info, found[1], name)
  if not entry then refuse("'" .. name .. "' is not in the `" .. section .. "` table", line_to_write, section) end
  entry = entry --[[@as table]]
  if not alone_on_lines(info, entry.first, entry.last, entry.comma) then refuse("the entry is not alone on its line", line_to_write, section) end
  local first_line = info.line_of(info.tokens[entry.first].start)
  local last_line = info.line_of(info.tokens[entry.comma or entry.last].stop)
  local start = info.line_starts[first_line]
  local stop = (info.line_starts[last_line + 1] or (#text + 1)) - 1
  local result = apply(text, { { start = start, stop = stop, text = "" } })
  verify(text, result, section, name, nil, line_to_write)
  return result
end

--- Whether `name` is in `section` of the manifest text (nil when the file cannot be analysed).
---@param text string
---@param section string
---@param name string
---@return boolean? present
function M.has(text, section, name)
  local ok, info = pcall(analyse, text, "", section)
  if not ok then return nil end
  for _, target in ipairs(info.sections[section] or {}) do
    if find_entry(info, target, name) then return true end
  end
  return false
end

return M
