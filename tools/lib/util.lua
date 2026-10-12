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
  if is_windows and cmd:find('^"') then cmd = '"' .. cmd .. '"' end
  local p = io.popen(cmd, "r")
  if not p then return "", false end
  local out = p:read("a")
  local ok = p:close()
  return (out:gsub("%s+$", "")), ok == true
end

--- Quotes a string as one shell argument (POSIX single quotes, Windows double quotes).
---@param s string
---@return string
function M.quote(s)
  if is_windows then return '"' .. s:gsub("/", "\\"):gsub('"', '""') .. '"' end
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

--- Returns the path of the running Lua interpreter.
---@return string
function M.interpreter() return arg and arg[-1] or "lua" end

--- Returns true when the path is an existing directory.
---@param path string
---@return boolean
function M.is_dir(path)
  local cmd = is_windows and ('if exist "%s\\nul" (exit 0) else (exit 1)'):format((path:gsub("/", "\\")))
    or ("test -d %s"):format(M.quote(path))
  local ok = os.execute(cmd .. (is_windows and " >nul 2>&1" or " >/dev/null 2>&1"))
  return ok == true
end

--- Creates a directory and its parents.
---@param path string
---@return boolean
function M.mkdir(path)
  local cmd = is_windows and ("mkdir %s >nul 2>&1"):format(M.quote(path)) or ("mkdir -p %s"):format(M.quote(path))
  return os.execute(cmd) == true
end

--- Lists the entries of a directory (names only), sorted.
---@param dir string
---@return string[]
function M.list_dir(dir)
  local cmd = is_windows and ("dir /b %s 2>nul"):format(M.quote(dir)) or ("ls -1 %s 2>/dev/null"):format(M.quote(dir))
  local out = M.capture(cmd)
  local names = {}
  for name in out:gmatch("[^\r\n]+") do names[#names + 1] = name end
  table.sort(names)
  return names
end

--- Returns true when a file or directory exists.
---@param path string
---@return boolean
function M.exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return M.is_dir(path)
end

--- Recursively lists files under dir whose name ends with suffix (paths keep dir as prefix).
---@param dir string
---@param suffix string
---@return string[]
function M.walk(dir, suffix)
  local files = {}
  local function visit(d)
    for _, name in ipairs(M.list_dir(d)) do
      local path = d .. "/" .. name
      if M.is_dir(path) then visit(path)
      elseif name:sub(-#suffix) == suffix then files[#files + 1] = path end
    end
  end
  visit(dir)
  return files
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
