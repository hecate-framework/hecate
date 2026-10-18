-- Syntax highlighting for fenced code blocks: small hand-written lexers for Lua (5.5,
-- including the `global` keyword and LuaLS `---@` annotations), JSON, shell, HTTP messages
-- and unified diffs. Unknown languages are escaped and left plain. The output only ever
-- contains `<span class="tk-...">` elements around escaped text.
global <const> string, table, ipairs, type, require

local html = require("hecate.doc.internal.html")

local escape = html.escape

local M = {}

---@alias hecate.doc.TokenClass
---| "keyword"
---| "string"
---| "comment"
---| "number"
---| "literal"
---| "annotation"
---| "property"
---| "function"
---| "variable"
---| "flag"
---| "inserted"
---| "deleted"
---| "meta"

--- Collects tokens, merging neighbouring plain text.
local function builder()
  local parts, plain = {}, {}
  local b = {}
  local function flush()
    if #plain > 0 then
      parts[#parts + 1] = escape(table.concat(plain))
      plain = {}
    end
  end
  function b.text(text) plain[#plain + 1] = text end
  function b.token(class, text)
    flush()
    parts[#parts + 1] = ("<span class=\"tk-%s\">%s</span>"):format(class, escape(text))
  end
  function b.result()
    flush()
    return table.concat(parts)
  end
  return b
end

local LUA_KEYWORDS = {}
for word in ([[and break do else elseif end for function global goto if in local not or repeat
  return then until while]]):gmatch("%a+") do
  LUA_KEYWORDS[word] = "keyword"
end
for _, word in ipairs({ "nil", "true", "false" }) do LUA_KEYWORDS[word] = "literal" end

--- Reads a quoted string starting at `i`; returns the index after it (an unterminated
--- string ends at the line end).
local function quoted_end(code, i, quote)
  local n, j = #code, i + 1
  while j <= n do
    local char = code:sub(j, j)
    if char == "\\" then
      j = j + 2
    elseif char == quote then
      return j + 1
    elseif char == "\n" then
      return j
    else
      j = j + 1
    end
  end
  return n + 1
end

local function lua_lexer(code)
  local out, i, n = builder(), 1, #code
  while i <= n do
    local char = code:sub(i, i)
    local equals = code:match("^%-%-%[(=*)%[", i)
    if equals then
      local _, finish = code:find("]" .. equals .. "]", i, true)
      finish = finish or n
      out.token("comment", code:sub(i, finish))
      i = finish + 1
    elseif code:find("^%-%-", i) then
      local finish = (code:find("\n", i, true) or n + 1) - 1
      local line = code:sub(i, finish)
      local dashes, tag, rest = line:match("^(%-%-%-)(@[%w_]+)(.*)$")
      if dashes then
        out.token("comment", dashes)
        out.token("annotation", tag)
        if rest ~= "" then out.token("comment", rest) end
      else
        out.token("comment", line)
      end
      i = finish + 1
    elseif char == '"' or char == "'" then
      local finish = quoted_end(code, i, char)
      out.token("string", code:sub(i, finish - 1))
      i = finish
    elseif code:find("^%[=*%[", i) then
      local level = code:match("^%[(=*)%[", i)
      local _, finish = code:find("]" .. level .. "]", i, true)
      finish = finish or n
      out.token("string", code:sub(i, finish))
      i = finish + 1
    elseif char:match("%d") or code:find("^%.%d", i) then
      local number = code:match("^0[xX][%x%.]+", i)
      if number then
        local exponent = code:match("^[pP][+-]?%d+", i + #number)
        number = number .. (exponent or "")
      else
        number = code:match("^%d*%.?%d*", i)
        local exponent = code:match("^[eE][+-]?%d+", i + #number)
        number = number .. (exponent or "")
      end
      out.token("number", number)
      i = i + #number
    elseif char:match("[%a_]") then
      local word = code:match("^[%w_]+", i)
      local class = LUA_KEYWORDS[word]
      if class then out.token(class, word) else out.text(word) end
      i = i + #word
    else
      out.text(char)
      i = i + 1
    end
  end
  return out.result()
end

local function json_lexer(code)
  local out, i, n = builder(), 1, #code
  while i <= n do
    local char = code:sub(i, i)
    if char == '"' then
      local finish = quoted_end(code, i, '"')
      local class = code:find("^%s*:", finish) and "property" or "string"
      out.token(class, code:sub(i, finish - 1))
      i = finish
    elseif char:match("[%d]") or (char == "-" and code:find("^%-%d", i)) then
      local number = code:match("^%-?%d+%.?%d*[eE]?[+-]?%d*", i)
      out.token("number", number)
      i = i + #number
    elseif char:match("%a") then
      local word = code:match("^%a+", i)
      if word == "true" or word == "false" or word == "null" then out.token("literal", word)
      else out.text(word) end
      i = i + #word
    else
      out.text(char)
      i = i + 1
    end
  end
  return out.result()
end

local SHELL_KEYWORDS = {}
for word in ("if then elif else fi for while until do done case esac in function select"):gmatch("%a+") do
  SHELL_KEYWORDS[word] = true
end

local function shell_lexer(code)
  local out = builder()
  local first = true -- the next word is a command name
  local i, n = 1, #code
  local at_line_start = true
  while i <= n do
    local char = code:sub(i, i)
    if at_line_start and code:find("^[$>#] ", i) and char ~= "#" then
      out.token("comment", char .. " ")
      i = i + 2
      at_line_start = false
      first = true
    elseif char == "#" and (i == 1 or code:sub(i - 1, i - 1):match("%s")) then
      local finish = (code:find("\n", i, true) or n + 1) - 1
      out.token("comment", code:sub(i, finish))
      i = finish + 1
    elseif char == '"' or char == "'" then
      local finish = quoted_end(code, i, char)
      out.token("string", code:sub(i, finish - 1))
      i = finish
      first = false
    elseif char == "$" and code:find("^%$[%w_{]", i) then
      local variable = code:match("^%${[^}\n]*}", i) or code:match("^%$[%w_]+", i)
      out.token("variable", variable)
      i = i + #variable
      first = false
    elseif char == "-" and code:find("^%-%-?[%w]", i) and (i == 1 or code:sub(i - 1, i - 1):match("%s")) then
      local flag = code:match("^%-%-?[%w_%-]+", i)
      out.token("flag", flag)
      i = i + #flag
    elseif char:match("[%w_./~]") then
      local word = code:match("^[%w_./~:@%%+,=-]+", i) or char
      if first and SHELL_KEYWORDS[word] then
        out.token("keyword", word)
      elseif first then
        out.token("function", word)
        first = false
      else
        out.text(word)
      end
      i = i + #word
    else
      if char == "\n" then
        first, at_line_start = true, true
      elseif char == "|" or char == ";" or char == "&" then
        first = true
      end
      if char ~= "\n" and char ~= " " then at_line_start = false end
      out.text(char)
      i = i + 1
    end
    if char ~= "\n" and at_line_start and char ~= " " then at_line_start = false end
  end
  return out.result()
end

local function http_lexer(code)
  local out = builder()
  local in_headers = true
  local first_line = true
  for line, newline in (code .. "\n"):gmatch("([^\n]*)(\n)") do
    if in_headers and line == "" then
      in_headers = false
      out.text(newline)
    elseif in_headers and first_line then
      local version, status, reason = line:match("^(HTTP/[%d.]+)%s+(%d+)%s*(.*)$")
      if version then
        out.token("keyword", version)
        out.text(" ")
        out.token("number", status)
        if reason ~= "" then out.text(" " .. reason) end
      else
        local method, target, tail = line:match("^(%u+)%s+(%S+)(.*)$")
        if method then
          out.token("keyword", method)
          out.text(" ")
          out.token("string", target)
          out.text(tail)
        else
          out.text(line)
        end
      end
      out.text(newline)
    elseif in_headers then
      local name, rest = line:match("^([%w%-]+)(:.*)$")
      if name then
        out.token("property", name)
        out.text(rest)
      else
        out.text(line)
      end
      out.text(newline)
    else
      out.text(line .. newline)
    end
    first_line = false
  end
  local result = out.result()
  return (result:gsub("\n$", ""))
end

local function diff_lexer(code)
  local out = builder()
  for line, newline in (code .. "\n"):gmatch("([^\n]*)(\n)") do
    if line:find("^@@") then
      out.token("meta", line)
    elseif line:find("^%+") and not line:find("^%+%+%+") then
      out.token("inserted", line)
    elseif line:find("^%-") and not line:find("^%-%-%-") then
      out.token("deleted", line)
    else
      out.text(line)
    end
    out.text(newline)
  end
  return (out.result():gsub("\n$", ""))
end

local LEXERS = {
  lua = lua_lexer,
  json = json_lexer,
  jsonc = json_lexer,
  sh = shell_lexer,
  bash = shell_lexer,
  zsh = shell_lexer,
  shell = shell_lexer,
  console = shell_lexer,
  http = http_lexer,
  diff = diff_lexer,
}

local LABELS = {
  lua = "Lua", json = "JSON", jsonc = "JSON", sh = "Shell", bash = "Shell", zsh = "Shell",
  shell = "Shell", console = "Shell", http = "HTTP", diff = "Diff", sql = "SQL", toml = "TOML",
  yaml = "YAML", yml = "YAML", text = "Text", txt = "Text", markdown = "Markdown", md = "Markdown",
  c = "C", html = "HTML", css = "CSS", js = "JavaScript",
}

--- Returns true when a lexer exists for the language.
---@param language string
---@return boolean
function M.supports(language) return LEXERS[language:lower()] ~= nil end

--- Returns the display label of a language (for the language label of a code block).
---@param language string
---@return string
function M.label(language)
  return LABELS[language:lower()] or language
end

--- Highlights `code`. The result is escaped HTML, safe to place inside `<code>`.
---@param language string  language name from the info string ("" for none)
---@param code string
---@return string html
function M.render(language, code)
  local lexer = LEXERS[language:lower()]
  if lexer then return lexer(code) end
  return escape(code)
end

return M
