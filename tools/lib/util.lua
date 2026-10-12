-- Shared helpers for repository tasks. Standard library only.
local M = {}

local is_windows = package.config:sub(1, 1) == "\\"

--- Returns true when running on Windows.
---@return boolean
function M.is_windows() return is_windows end

--- Runs a command and returns its trimmed standard output and success flag.
---@param cmd string
---@return string output
---@return boolean ok
function M.capture(cmd)
  local p = io.popen(cmd, "r")
  if not p then return "", false end
  local out = p:read("a")
  local ok = p:close()
  return (out:gsub("%s+$", "")), ok == true
end

--- Lists the entries of a directory (names only), sorted.
---@param dir string
---@return string[]
function M.list_dir(dir)
  local cmd = is_windows and ('dir /b "%s" 2>nul'):format(dir) or ('ls -1 "%s" 2>/dev/null'):format(dir)
  local out = M.capture(cmd)
  local names = {}
  for name in out:gmatch("[^\r\n]+") do names[#names + 1] = name end
  table.sort(names)
  return names
end

--- Returns true when a file or directory exists (directories are probed with "/.").
---@param path string
---@return boolean
function M.exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  f = io.open(path .. "/.", "r")
  if f then f:close() return true end
  return false
end

--- Minimal JSON encoder for reports (arrays, objects with string keys, scalars).
---@param v any
---@return string
function M.json(v)
  local t = type(v)
  if t == "string" then
    return '"' .. v:gsub('[%c"\\]', function(c)
      local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
      return map[c] or ("\\u%04x"):format(c:byte())
    end) .. '"'
  elseif t == "table" then
    if #v > 0 or next(v) == nil then
      local parts = {}
      for i, x in ipairs(v) do parts[i] = M.json(x) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for i, k in ipairs(keys) do parts[i] = M.json(k) .. ":" .. M.json(v[k]) end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return tostring(v)
end

return M
