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

--- The command that runs the system's own `tar` (bsdtar). On Windows a `tar` found first on PATH may be another
--- program: Git for Windows' GNU tar misreads `C:` as a remote host and cannot read a zip, so the one of System32 is
--- named. `windows` and `system_root` are injectable so that the choice is testable on every platform.
---@param windows? boolean   defaults to the running platform
---@param system_root? string   defaults to %SystemRoot%
---@return string command   ready to put at the start of a shell command line
function M.tar_command(windows, system_root)
  if windows == nil then windows = is_windows end
  if not windows then return "tar" end
  local root = system_root or os.getenv("SystemRoot") or "C:\\Windows"
  return '"' .. (root .. "\\System32\\tar.exe"):gsub('"', '""') .. '"'
end

--- Returns the path of the running Lua interpreter.
---@return string
function M.interpreter() return arg and arg[-1] or "lua" end

--- Returns true when the path is an existing directory.
---@param path string
---@return boolean
function M.is_dir(path)
  -- `cd /d` in the child `cmd` fails for a missing path and for a file (the older `if exist "dir\nul"` test was false for an existing
  -- directory that holds files, on the Windows CI runners)
  local cmd = is_windows and ('cd /d "%s"'):format((path:gsub("/", "\\")))
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

--- Creates a new, empty directory `<base>/<prefix>-<time>-<random>` (and `base`) and returns its path, or nil. A
--- repository task keeps its scratch files under `.hecate/` (git-ignored) rather than in the system temporary directory,
--- where `os.tmpname()` leaves a file behind and its name is predictable.
---@param base string
---@param prefix string
---@return string?
function M.make_temp_dir(base, prefix)
  for _ = 1, 10 do
    local path = ("%s/%s-%d-%d"):format(base, prefix, os.time(), math.random(1, 1 << 30))
    if not M.exists(path) and M.mkdir(path) then return path end
  end
  return nil
end

--- Removes a directory and everything under it (no error when it is absent).
---@param path string
---@return boolean
function M.remove_tree(path)
  if path == "" or path == "/" or path == "." then return false end
  local cmd = is_windows and ("rmdir /s /q %s >nul 2>&1"):format(M.quote(path)) or ("rm -rf %s"):format(M.quote(path))
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
