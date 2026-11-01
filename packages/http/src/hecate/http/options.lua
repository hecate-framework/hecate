-- Helpers for the messages of option errors: a validated option value is quoted for the programmer who wrote it
-- (short, control characters replaced), and an unknown name gets its nearest valid one. Peer data never goes through here.
global <const> require, type, string, math, tostring, ipairs, pairs, table

--- Messages of option errors.
---@class hecate.http.optiontext
local options = {}

--- Shows an option value in a message: a string quoted and cut to 40 characters, a number or boolean as is, anything else
--- by its type.
---@param value any
---@return string
function options.show(value)
  local kind = type(value)
  if kind == "string" then
    local text = string.gsub(value, "[%c\127]", "?")
    if #text > 40 then text = string.sub(text, 1, 40) .. "..." end
    return '"' .. text .. '"'
  end
  if kind == "number" or kind == "boolean" then return tostring(value) end
  return "a " .. kind
end

---@param a string
---@param b string
---@return integer
local function distance(a, b)
  local previous = {}
  for j = 0, #b do previous[j] = j end
  for i = 1, #a do
    local current = { [0] = i }
    for j = 1, #b do
      local cost = string.sub(a, i, i) == string.sub(b, j, j) and 0 or 1
      current[j] = math.min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
    end
    previous = current
  end
  return previous[#b]
end

--- The nearest name of `known` (a set) to `name`, when it is at most two edits away.
---@param name any
---@param known table<string, boolean>
---@return string?
function options.suggest(name, known)
  if type(name) ~= "string" or #name > 40 then return nil end
  local best, best_distance
  local names = {}
  for candidate in pairs(known) do names[#names + 1] = candidate end
  table.sort(names)
  for _, candidate in ipairs(names) do
    local d = distance(name, candidate)
    if d <= 2 and (best == nil or d < best_distance) then best, best_distance = candidate, d end
  end
  return best
end

--- The text of an unknown-option error for `owner` (`http.Server`).
---@param owner string
---@param key any
---@param known table<string, boolean>
---@return string
function options.unknown(owner, key, known)
  local suggestion = options.suggest(key, known)
  local shown = type(key) == "string" and options.show(key) or "key"
  return ("%s: unknown option %s%s"):format(owner, shown, suggestion and (" (did you mean " .. suggestion .. "?)") or "")
end

return options
