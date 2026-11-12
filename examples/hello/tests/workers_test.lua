-- The Phase 2 exit criterion: the example served by two worker processes (ADR 0023). This process is the primary
-- (`workers = 2`, `round_robin`); each worker is `main.lua` itself, started again by the supervisor, so the entry point
-- a user runs is the one tested. The test asks the primary to stop (`Application:shutdown`) instead of raising a signal,
-- so it runs on the three platforms.
---@diagnostic disable: need-check-nil, param-type-mismatch, missing-fields, undefined-field, inject-field
local test = require("harness.test")
local uv = require("luv")
local net = require("hecate.net")
local reactor = require("hecate.reactor")
local log = require("hecate.log")
local hello = require("hello")
local T = test.Case("HelloWorkersTest")

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]tests[/\\][^/\\]+$") or "."
local main_script = uv.fs_realpath(here .. "/main.lua") or here .. "/main.lua"
local wire = dofile(here .. "/tests/helpers/wire.lua")

--- Makes the relative entries of a search path absolute.
local function absolute(search_path)
  local entries = {}
  for entry in search_path:gmatch("[^;]+") do
    local resolved = entry
    if not (entry:match("^[/\\]") or entry:match("^%a:") or entry:match("^!")) then resolved = uv.cwd() .. "/" .. entry end
    entries[#entries + 1] = resolved
  end
  return table.concat(entries, ";")
end

--- Gives the workers (they inherit this process's environment) the search paths of this process while `body` runs.
local function with_lua_paths(body)
  local names = { "LUA_PATH", "LUA_PATH_5_5", "LUA_CPATH", "LUA_CPATH_5_5" }
  local saved = {}
  for _, name in ipairs(names) do saved[name] = uv.os_getenv(name) end
  local path, cpath = absolute(package.path), absolute(package.cpath)
  uv.os_setenv("LUA_PATH", path); uv.os_setenv("LUA_PATH_5_5", path)
  uv.os_setenv("LUA_CPATH", cpath); uv.os_setenv("LUA_CPATH_5_5", cpath)
  local ok, err = pcall(body)
  for _, name in ipairs(names) do
    if saved[name] then uv.os_setenv(name, saved[name]) else uv.os_unsetenv(name) end
  end
  if not ok then error(err, 0) end
end

--- One request on its own connection (`Connection: close`, so round robin sees a new connection each time); returns
--- the status and the body, or nil when the connection ended without an answer (no worker ready yet).
local function request(port, method, path, content)
  local stream = net.connect("127.0.0.1", port)
  local head = ("%s %s HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n"):format(method, path)
  if content then
    head = head .. ("Content-Type: application/json\r\nContent-Length: %d\r\n"):format(#content)
  end
  stream:write(head .. "\r\n" .. (content or ""))
  local parts = {}
  while true do
    local ok, data = pcall(stream.read, stream)
    if not ok or data == nil then break end
    parts[#parts + 1] = data
  end
  stream:close()
  local answer = table.concat(parts)
  local status = answer:match("^HTTP/1%.1 (%d%d%d)")
  if status == nil then return nil end
  return tonumber(status), answer:match("\r\n\r\n(.*)$")
end

function T:test_two_workers_serve_the_example_and_stop_on_shutdown()
  local app = hello.application({
    workers = 2, strategy = "round_robin", grace_timeout = 5, signals = false,
    worker_command = { uv.exepath(), main_script },
    logger = log.Logger({ sinks = { log.MemorySink() } }), server = { host = "127.0.0.1", port = 0 },
  })
  local answers, invalid, ok, err = {}, nil, nil, nil
  with_lua_paths(function()
    reactor.run(function()
      reactor.fork(function()
        local inner_ok, inner_err = pcall(reactor.deadline, 30, function()
          while not app:local_address() do reactor.sleep(0.02) end
          local port = app:local_address().port
          while request(port, "GET", "/health") == nil do reactor.sleep(0.05) end -- a worker is ready
          for i = 1, 6 do answers[i] = { request(port, "GET", "/hello/Ada") } end
          invalid = { request(port, "POST", "/greetings", '{"name":""}') }
        end)
        app:shutdown(5)
        if not inner_ok then error(inner_err, 0) end
      end)
      ok, err = pcall(reactor.deadline, 40, app.serve, app)
    end)
  end)
  self:assert_true(ok, tostring(err))
  self:assert_equal(6, #answers)
  for _, answer in ipairs(answers) do
    self:assert_equal(200, answer[1])
    self:assert_true(answer[2]:find('"Hello, Ada!"', 1, true) ~= nil, answer[2])
  end
  self:assert_equal(422, invalid[1])
  self:assert_true(invalid[2]:find('"source"%s*:%s*"content"') ~= nil, invalid[2])
  self:assert_nil(app:local_address())
end

function T:test_a_request_in_flight_in_a_worker_is_answered_when_the_primary_shuts_down()
  local app = hello.application({
    workers = 2, strategy = "round_robin", grace_timeout = 5, signals = false,
    worker_command = { uv.exepath(), main_script },
    logger = log.Logger({ sinks = { log.MemorySink() } }), server = { host = "127.0.0.1", port = 0 },
  })
  local response, refused, ok, err
  with_lua_paths(function()
    reactor.run(function()
      reactor.fork(function()
        local inner_ok, inner_err = pcall(reactor.deadline, 30, function()
          while not app:local_address() do reactor.sleep(0.02) end
          local port = app:local_address().port
          while request(port, "GET", "/health") == nil do reactor.sleep(0.05) end -- a worker is ready
          -- `stop` runs in a computation of its own: `shutdown` returns once the workers have drained.
          response, refused = wire.request_in_flight_during_shutdown(reactor, port, function() app:shutdown(5) end)
        end)
        if not inner_ok then
          app:shutdown(5)
          error(inner_err, 0)
        end
      end)
      ok, err = pcall(reactor.deadline, 40, app.serve, app)
    end)
  end)
  self:assert_true(ok, tostring(err))
  self:assert_true(refused, "the primary refuses new connections while the worker drains")
  self:assert_not_nil(response, "the request in flight in the worker is answered")
  self:assert_equal(201, response.status)
  self:assert_true(response.body:find('"Hola, Ada!"', 1, true) ~= nil, response.body)
  self:assert_true(response.head:lower():find("\r\nconnection: close", 1, true) ~= nil, response.head)
  self:assert_nil(app:local_address())
end

return T
