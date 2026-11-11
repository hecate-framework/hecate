-- Helpers shared by the tests that start real worker processes (tests/integration): where the fixtures are, the
-- environment that gives a worker the search paths of the test process, the platform gate, one HTTP request, a wait on
-- an observable state and the log of a supervisor. Not a test: it is loaded with `dofile` from a test file.
local uv = require("luv")
local net = require("hecate.net")
local reactor = require("hecate.reactor")

local helpers = {}

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]helpers[/\\][^/\\]+$") or "."

--- The absolute path of a program of `tests/fixtures`.
---@param name string
---@return string
function helpers.fixture(name)
  local path = here .. "/fixtures/" .. name
  return uv.fs_realpath(path) or path
end

--- Makes the relative entries of a search path absolute (a worker may start in another directory).
---@param search_path string
---@return string
function helpers.absolute(search_path)
  local entries = {}
  for entry in search_path:gmatch("[^;]+") do
    local resolved = entry
    if not (entry:match("^[/\\]") or entry:match("^%a:") or entry:match("^!")) then resolved = uv.cwd() .. "/" .. entry end
    entries[#entries + 1] = resolved
  end
  return table.concat(entries, ";")
end

--- The environment of a worker: the search paths of this process, plus `extra`.
---@param extra? table<string, string>
---@return table<string, string>
function helpers.lua_env(extra)
  local path, cpath = helpers.absolute(package.path), helpers.absolute(package.cpath)
  local env = { LUA_PATH = path, LUA_PATH_5_5 = path, LUA_CPATH = cpath, LUA_CPATH_5_5 = cpath }
  for name, value in pairs(extra or {}) do env[name] = value end
  return env
end

--- Tells whether the platform can run workers; prints why not when it cannot (the test then returns).
---@return boolean
function helpers.can_run_workers()
  for _, query in ipairs({ reactor.supports_spawn, reactor.supports_handle_passing }) do
    local supported, reason = query()
    if not supported then
      io.stderr:write("# SKIP: workers are not supported here: ", tostring(reason), "\n")
      return false
    end
  end
  return true
end

--- Whether the signals of the platform can be raised with `uv.kill` (console signals only on Windows).
---@return boolean
function helpers.can_raise_signals()
  return not uv.os_uname().sysname:match("Windows")
end

--- Waits (at most `seconds`, default 20) until `predicate()` holds; fails with a deadline error otherwise. The state is
--- observable (a counter, a log code), never a duration that is hoped to be enough.
---@async
---@param predicate fun(): any
---@param seconds? number
function helpers.wait_until(predicate, seconds)
  reactor.deadline(seconds or 20, function()
    while not predicate() do reactor.sleep(0.005) end
  end)
end

--- One request with `Connection: close`; the content, or nil when the connection ended without an answer.
---@async
---@param port integer
---@param path? string  default "/"
---@return string?
function helpers.get(port, path)
  local ok, stream = pcall(net.connect, "127.0.0.1", port)
  if not ok then return nil end
  stream:write(("GET %s HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"):format(path or "/"))
  local parts = {}
  while true do
    local read_ok, data = pcall(stream.read, stream)
    if not read_ok or data == nil then break end
    parts[#parts + 1] = data
  end
  stream:close()
  return table.concat(parts):match("\r\n\r\n(.*)$")
end

--- Whether a process of this id exists (signal 0 delivers nothing).
---@param pid integer|string
---@return boolean
function helpers.alive(pid)
  return uv.kill(tonumber(pid) --[[@as integer]], 0) == 0
end

--- The log records that carry a `code`, in order: `{ code, worker, pid }`.
---@param memory { records: fun(self: any): table[] }  a `hecate.log.MemorySink`
---@return { code: string, worker: integer?, pid: integer? }[]
function helpers.events(memory)
  local list = {}
  for _, record in ipairs(memory:records()) do
    local fields = record.fields
    if fields and fields.code then list[#list + 1] = { code = fields.code, worker = fields.worker, pid = fields.pid } end
  end
  return list
end

--- The first event with `code`, or nil.
---@param memory { records: fun(self: any): table[] }  a `hecate.log.MemorySink`
---@param code string
---@return { code: string, worker: integer?, pid: integer? }?
function helpers.find_event(memory, code)
  for _, event in ipairs(helpers.events(memory)) do
    if event.code == code then return event end
  end
  return nil
end

--- The codes of the events, joined by commas, keeping those that start with `prefix` (all by default).
---@param memory { records: fun(self: any): table[] }  a `hecate.log.MemorySink`
---@param prefix? string
---@return string
function helpers.codes(memory, prefix)
  local list = {}
  for _, event in ipairs(helpers.events(memory)) do
    if prefix == nil or event.code:sub(1, #prefix) == prefix then list[#list + 1] = event.code end
  end
  return table.concat(list, ",")
end

return helpers
