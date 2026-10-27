-- LuaLS annotation scan of a library source file (check-annotations; coding-standards.md,
-- "Annotations for the reference"; ADR 0018).
--
-- What it sees (text scan, no parser): comments and strings are blanked, then
--   * the table a file returns (`return T` or `return core.finalise(T)`) and every `local T`
--     carrying a `---@class` are the *module tables*;
--   * at column 0, `function T.name(...)`, `function T:name(...)` and `T.name = function(...)`
--     on a module table are the *exported functions* (names starting with `_`, and any
--     function whose comment block holds `---@private`, `---@package` or `---@protected`,
--     are not exported);
--   * the body of such a function is found by counting block keywords, so a `return` inside a
--     nested function is not attributed to the exported one;
--   * `T.name = <literal>` (number, string, boolean, table constructor) at column 0 is an
--     exported field.
-- It checks, per exported function: a `---` comment block exists; every parameter (except
-- `self`) has a `---@param`; a function that returns a value has a `---@return`; a function
-- that contains `return nil` (absence) has a nullable `---@return` (`T?`, `T|nil`, `nil`).
-- Per module table: a `---@class` above `local T`. Per exported field: a `---` comment above
-- it or a `---@field` of that name in the file.
--
-- What it cannot see: functions defined on nested tables (`function T.a.b`), in loops or
-- indented blocks, or assigned through a local alias; re-exports (`T.f = other.f`, whose
-- annotations are checked where `other.f` is defined); whether a declared type is correct;
-- absence signalled through a call (`return helper()` that yields nil) or an implicit end
-- without `return`; `---@async` consistency (not part of this version: pending an owner
-- decision, finding A42). `-- annotations-ok` on the definition line accepts an exception.
local M = {}

--- Blanks comments and the content of strings (newlines and offsets are preserved).
---@param src string
---@return string
local function blank(src)
  local out, n, i, len = {}, 0, 1, #src
  local function put(s) n = n + 1; out[n] = s end
  local function spaces(s) return (s:gsub("[^\n]", " ")) end
  while i <= len do
    local c = src:sub(i, i)
    if c == "-" and src:sub(i, i + 1) == "--" then
      local eq = src:match("^%-%-%[(=*)%[", i)
      local stop
      if eq then
        local _, e = src:find("]" .. eq .. "]", i, true)
        stop = e or len
      else
        stop = (src:find("\n", i, true) or len + 1) - 1
      end
      put(spaces(src:sub(i, stop)))
      i = stop + 1
    elseif c == '"' or c == "'" then
      local j = i + 1
      while j <= len do
        local d = src:sub(j, j)
        if d == "\\" then j = j + 2
        elseif d == c or d == "\n" then break
        else j = j + 1 end
      end
      put(c .. spaces(src:sub(i + 1, j - 1)) .. c)
      i = j + 1
    elseif c == "[" and src:match("^%[=*%[", i) then
      local eq = src:match("^%[(=*)%[", i)
      local _, e = src:find("]" .. eq .. "]", i, true)
      e = e or len
      put("[" .. spaces(src:sub(i + 1, e - 1)) .. "]")
      i = e + 1
    else
      put(c)
      i = i + 1
    end
  end
  return table.concat(out)
end

local OPENERS = { ["function"] = true, ["if"] = true, ["do"] = true, ["repeat"] = true }
local CLOSERS = { ["end"] = true, ["until"] = true }
local NO_VALUE = { ["end"] = true, ["else"] = true, ["elseif"] = true, ["until"] = true }

--- Walks the function whose `function` keyword is at `from`; returns the end offset, whether it
--- returns a value and whether it returns nil explicitly (nested functions are not counted).
---@param code string
---@param from integer
---@return integer stop, boolean has_value, boolean has_absence
local function analyse(code, from)
  local depth, nfunc, has_value, has_absence = 0, 0, false, false
  local kinds = {}
  local pos = from
  while true do
    local s, e = code:find("[%a_][%w_]*", pos)
    if not s then return #code, has_value, has_absence end
    local word = code:sub(s, e)
    pos = e + 1
    if OPENERS[word] then
      depth = depth + 1
      kinds[depth] = word
      if word == "function" then nfunc = nfunc + 1 end
    elseif CLOSERS[word] then
      if kinds[depth] == "function" then nfunc = nfunc - 1 end
      kinds[depth] = nil
      depth = depth - 1
      if depth == 0 then return e, has_value, has_absence end
    elseif word == "return" and nfunc == 1 then
      local ns, ne = code:find("[%a_][%w_]*", pos)
      local nxt = ns and code:sub(ns, ne)
      local between = ns and code:sub(pos, ns - 1) or code:sub(pos)
      if nxt and not NO_VALUE[nxt] and between:match("^%s*$") then
        if nxt == "nil" then has_absence = true else has_value = true end
      elseif not between:match("^%s*$") then
        has_value = true -- `return (x)`, `return "s"`, `return -1`, ...
      end
    end
  end
end

--- Returns the lines of the contiguous `---` block directly above line `n`.
---@param lines string[]
---@param n integer
---@return string[]
local function block_above(lines, n)
  local out = {}
  local i = n - 1
  while i >= 1 and lines[i]:match("^%s*%-%-%-") do
    table.insert(out, 1, lines[i])
    i = i - 1
  end
  return out
end

local function has_tag(block, tag)
  for _, l in ipairs(block) do
    if l:match("^%s*%-%-%-@" .. tag .. "%f[^%w_]") then return true end
  end
  return false
end

local function nullable(type_text)
  return type_text:find("?", 1, true) ~= nil or type_text:find("%f[%w_]nil%f[^%w_]") ~= nil
end

--- Scans one source; returns { line, name, message }[].
---@param source string
---@return { line: integer, name: string, message: string }[]
function M.scan(source)
  local found = {}
  local function report(line, name, message) found[#found + 1] = { line = line, name = name, message = message } end
  local lines = {}
  for l in (source .. "\n"):gmatch("(.-)\r?\n") do lines[#lines + 1] = l end
  local code = blank(source)
  local clines, offsets = {}, {}
  -- Line offsets are taken from `code`, which keeps the original line terminators.
  do
    local p = 1
    for i = 1, #lines do
      offsets[i] = p
      local nl = code:find("\n", p, true)
      clines[i] = code:sub(p, (nl or #code + 1) - 1):gsub("\r$", "")
      p = (nl or #code) + 1
    end
  end

  -- Module tables: the returned identifier and every `local T` under a `---@class`.
  local modules, unclassed, exports = {}, nil, 0
  local returned = code:match("\nreturn%s+([%a_][%w_]*)%s*$") or code:match("^return%s+([%a_][%w_]*)%s*$")
    or code:match("\nreturn%s+[%a_][%w_%.]*%(%s*([%a_][%w_]*)%s*%)%s*$")
  if returned then modules[returned] = true end
  for i, l in ipairs(clines) do
    local name = l:match("^local%s+([%a_][%w_]*)")
    if name then
      local block = block_above(lines, i)
      local is_class = false
      for _, b in ipairs(block) do
        if b:match("^%s*%-%-%-@class%f[^%w_]") then is_class = true end
      end
      if is_class then modules[name] = true end
      if name == returned and not is_class and not lines[i]:find("annotations%-ok") then
        unclassed = { line = i, name = name }
      end
    end
  end

  for i, l in ipairs(clines) do
    local recv, sep, name, fn_at
    local a, b, c = l:match("^function%s+([%a_][%w_]*)([.:])([%a_][%w_]*)%s*%(")
    if a then
      recv, sep, name = a, b, c
      fn_at = offsets[i]
    else
      a, c = l:match("^([%a_][%w_]*)%.([%a_][%w_]*)%s*=%s*function%s*%(")
      if a then
        recv, sep, name = a, ".", c
        fn_at = offsets[i] + l:find("function", 1, true) - 1
      end
    end
    if recv and modules[recv] and name:sub(1, 1) ~= "_" then
      local block = block_above(lines, i)
      local private = has_tag(block, "private") or has_tag(block, "package") or has_tag(block, "protected")
      if not private and not lines[i]:find("annotations%-ok") then
        if unclassed and recv == unclassed.name then exports = exports + 1 end
        local label = recv .. sep .. name
        local _, has_value, has_absence = analyse(code, fn_at)
        local params = code:match("^%s*%(([^)]*)%)", code:find("(", fn_at, true))
        local params_list = {}
        for raw in (params or ""):gmatch("[^,]+") do
          local p = raw:match("^%s*(.-)%s*$")
          if p ~= "" and p ~= "self" then params_list[#params_list + 1] = p end
        end
        local typed = has_tag(block, "type") or has_tag(block, "overload")
        if #block == 0 then
          report(i, label, "exported function has no `---` annotation block")
        elseif not typed then
          for _, p in ipairs(params_list) do
            local found_param = false
            for _, bl in ipairs(block) do
              local pn = bl:match("^%s*%-%-%-@param%s+([^%s]+)")
              if pn and (pn == p or pn == p .. "?") then found_param = true end
            end
            if not found_param then report(i, label, "parameter `" .. p .. "` has no `---@param`") end
          end
          local returns = {}
          for _, bl in ipairs(block) do
            local rest = bl:match("^%s*%-%-%-@return%s+(.*)$")
            if rest then returns[#returns + 1] = rest:match("^(.-)%s%s") or rest end
          end
          if (has_value or has_absence) and #returns == 0 then
            report(i, label, "returns a value but has no `---@return`")
          elseif has_absence then
            local ok = false
            for _, r in ipairs(returns) do if nullable(r) then ok = true end end
            if not ok then
              report(i, label, "returns `nil` for absence but no `---@return` is nullable (`T?`, ADR 0018)")
            end
          end
        end
      end
    end
    -- Exported literal field.
    local fr, fname = l:match("^([%a_][%w_]*)%.([%a_][%w_]*)%s*=%s*[%d\"'{%-tf]")
    if fr and modules[fr] and fname:sub(1, 1) ~= "_" and not lines[i]:find("annotations%-ok") then
      local rhs = l:match("=%s*(.*)$")
      local literal = rhs:match("^[%d\"'{]") or rhs:match("^%-%d") or rhs:match("^true%f[^%w_]")
        or rhs:match("^false%f[^%w_]")
      local documented = #block_above(lines, i) > 0 or source:find("---@field%s+" .. fname .. "%f[^%w_]") ~= nil
      if literal and unclassed and fr == unclassed.name then exports = exports + 1 end
      if literal and not documented then
        report(i, fr .. "." .. fname, "exported field has no `---` comment or `---@field`")
      end
    end
  end
  -- A returned table that carries exported functions or fields is a class of the reference.
  if unclassed and exports > 0 then
    table.insert(found, 1, { line = unclassed.line, name = unclassed.name,
      message = "the module table `" .. unclassed.name .. "` has exported members but no `---@class` above its declaration" })
  end
  return found
end

return M
