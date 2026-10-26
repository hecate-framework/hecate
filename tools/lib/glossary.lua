-- Glossary deny-list (docs/glossary.md, "Instead of" columns), restricted to terms that are
-- never acceptable in identifiers. Context-dependent terms (event, signal, table, row,
-- cache, queue, lock, timeout, ...) are deliberately absent: reviewers judge them.
local M = {}

---@type table<string, string>  discouraged term (lowercase words) -> preferred term
M.denied = {
  ["fiber"] = "coroutine",
  ["green thread"] = "coroutine",
  ["promise"] = "future",
  ["spawn"] = "fork (a coroutine; an operating-system process keeps `spawn`, marked glossary-ok)",
  ["nursery"] = "scope",
  ["task group"] = "scope",
  ["limiter"] = "semaphore",
  ["service locator"] = "container",
  ["middleware"] = "filter",
  ["mixin"] = "trait",
  ["dao"] = "repository",
  ["view model"] = "value object",
  ["entity manager"] = "unit of work",
}

--- Splits an identifier into lowercase words (snake_case and camelCase).
---@param ident string
---@return string[]
function M.words(ident)
  local s = ident:gsub("(%l)(%u)", "%1_%2"):lower()
  local out = {}
  for w in s:gmatch("[%l%d]+") do out[#out + 1] = w end
  return out
end

--- Returns { line, ident, preferred } for each discouraged identifier in the source.
---@param source string
---@return { line: integer, ident: string, preferred: string }[]
function M.scan(source)
  local found, n = {}, 0
  source = source:gsub("%-%-%[(=*)%[.-%]%1%]", function(m) return (m:gsub("[^\n]", "")) end)
  for line in (source .. "\n"):gmatch("(.-)\r?\n") do
    n = n + 1
    if not line:find("glossary%-ok") then
      local code = line:gsub("%-%-.*$", ""):gsub('"[^"]*"', '""'):gsub("'[^']*'", "''")
      for ident in code:gmatch("[%a_][%w_]*") do
        local words = M.words(ident)
        local joined = " " .. table.concat(words, " ") .. " "
        for term, preferred in pairs(M.denied) do
          if joined:find(" " .. term .. " ", 1, true) then
            found[#found + 1] = { line = n, ident = ident, preferred = preferred }
            break
          end
        end
      end
    end
  end
  return found
end

return M
