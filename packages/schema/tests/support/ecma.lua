-- A small independent backtracking matcher over the ECMA-262 subset that `hecate.schema.pattern` emits (no regex library in
-- Lua): sequences, groups, sets with ranges, `\xHH` escapes and the classes `\s` and `\S` (inside a set only: that is where
-- the translator writes them, `.` becoming `[\s\S]`), anchors, and the quantifiers `*`, `+`, `?` with their lazy forms.
-- `matches(re, subject)` raises on a construct outside the subset (a back reference, a non-capturing group, `\s` outside a
-- set), so that a test can tell "outside the subset" from "does not match".
local M = {}

function M.matches(re, subject)
  -- parse into items
  local pos = 1
  local function parse_seq(stop_at_paren)
    local seq = {}
    while pos <= #re do
      local c = re:sub(pos, pos)
      if c == ")" then
        if stop_at_paren then return seq end
        error("unbalanced")
      end
      local item
      if c == "^" then item = { t = "bol" }; pos = pos + 1
      elseif c == "$" then item = { t = "eol" }; pos = pos + 1
      elseif c == "(" then
        pos = pos + 1
        local inner = parse_seq(true)
        pos = pos + 1
        item = { t = "group", seq = inner }
      elseif c == "[" then
        local neg = re:sub(pos + 1, pos + 1) == "^"
        pos = pos + (neg and 2 or 1)
        local ranges = {}
        local function atom()
          local ch = re:sub(pos, pos)
          if ch == "\\" then
            local n = re:sub(pos + 1, pos + 1)
            if n == "x" then
              local v = tonumber(re:sub(pos + 2, pos + 3), 16); pos = pos + 4; return v
            end
            pos = pos + 2
            if n == "s" or n == "S" then return { class = n } end
            return ({ t = 9, n = 10, f = 12, r = 13 })[n] or n:byte()
          end
          pos = pos + 1
          return ch:byte()
        end
        while re:sub(pos, pos) ~= "]" do
          local lo = atom()
          if type(lo) == "table" then
            ranges[#ranges + 1] = lo
          elseif re:sub(pos, pos) == "-" and re:sub(pos + 1, pos + 1) ~= "]" then
            pos = pos + 1
            ranges[#ranges + 1] = { lo, atom() }
          else
            ranges[#ranges + 1] = { lo, lo }
          end
        end
        pos = pos + 1
        item = { t = "set", neg = neg, ranges = ranges }
      elseif c == "\\" then
        local n = re:sub(pos + 1, pos + 1)
        if n == "s" or n == "S" then error("unexpected") end
        pos = pos + 2
        item = { t = "set", neg = false, ranges = { { n:byte(), n:byte() } } }
      else
        pos = pos + 1
        item = { t = "set", neg = false, ranges = { { c:byte(), c:byte() } } }
      end
      local q = re:sub(pos, pos)
      if q == "*" or q == "+" or q == "?" then
        pos = pos + 1
        local lazy = false
        if re:sub(pos, pos) == "?" then lazy = true; pos = pos + 1 end
        item = { t = "rep", item = item, min = q == "+" and 1 or 0, max = q == "?" and 1 or math.huge, lazy = lazy }
      end
      seq[#seq + 1] = item
    end
    return seq
  end
  local ast = parse_seq(false)
  local function one(item, i)
    if item.t ~= "set" or i > #subject then return false end
    local b = subject:byte(i)
    local inside = false
    for _, r in ipairs(item.ranges) do
      if r.class then
        local space = b == 32 or (b >= 9 and b <= 13)
        if space == (r.class == "s") then inside = true end
      elseif b >= r[1] and b <= r[2] then
        inside = true
      end
    end
    return inside ~= item.neg
  end
  local match_seq
  local function match_item(item, i, k)
    if item.t == "bol" then return i == 1 and k(i) end
    if item.t == "eol" then return i == #subject + 1 and k(i) end
    if item.t == "set" then return one(item, i) and k(i + 1) end
    if item.t == "group" then return match_seq(item.seq, 1, i, k) end
    if item.t == "rep" then
      local function try(count, at)
        local function more() return count < item.max and match_item(item.item, at, function(j) return j > at and try(count + 1, j) end) end
        if item.lazy then
          return (count >= item.min and k(at)) or more()
        end
        return more() or (count >= item.min and k(at))
      end
      return try(0, i)
    end
  end
  match_seq = function(seq, n, i, k)
    if n > #seq then return k(i) end
    return match_item(seq[n], i, function(j) return match_seq(seq, n + 1, j, k) end)
  end
  for start = 1, #subject + 1 do
    if match_seq(ast, 1, start, function() return true end) then return true end
  end
  return false
end

return M
