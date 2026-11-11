-- Graceful shutdown through `Application` with requests in flight (ADR 0023; http-and-routing.md): `shutdown(grace)` stops
-- accepting at once, lets a request that is being served finish within the grace period, and cancels it when the period
-- ends. One process, real sockets on the loopback interface; the slow action waits on a channel the test controls, so no
-- test depends on how long anything takes.
local test = require("harness.test")
local core = require("hecate.core")
local net = require("hecate.net")
local reactor = require("hecate.reactor")
local log = require("hecate.log")
local kernel = require("hecate.kernel")
local T = test.Case("ApplicationShutdownTest")

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]integration[/\\][^/\\]+$") or "."
local workers = dofile(here .. "/helpers/workers.lua")
local wait_until, get = workers.wait_until, workers.get

--- An application whose `/slow` action reports that it started (`started`), then waits for `release` (or for its
--- cancellation, which it records in `state.cancelled`).
local function slow_application()
  local state = { started = reactor.Channel(8), release = reactor.Channel(8), cancelled = false, finished = false }
  local routes = kernel.routes("slow")
  routes:get("/slow", { action = function()
    state.started:send(true)
    local ok, err = pcall(state.release.receive, state.release)
    if not ok then
      state.cancelled = core.is_instance_of(err, core.CancellationError)
      error(err, 0)
    end
    state.finished = true
    return { done = true }
  end })
  routes:get("/fast", { action = function() return { fast = true } end })
  state.app = kernel.Application({
    routes = { routes }, signals = false, logger = log.Logger({ sinks = {} }), server = { host = "127.0.0.1", port = 0 },
  })
  return state
end

--- Whether a new connection to `port` is refused (a successful probe is closed).
local function refused(port)
  local ok, stream = pcall(net.connect, "127.0.0.1", port)
  if ok then stream:close() end
  return not ok
end

function T:test_shutdown_lets_a_request_in_flight_finish_and_refuses_new_connections()
  local state = slow_application()
  local app = state.app
  local body, served_ok, shutdown_returned_early
  reactor.run(function()
    reactor.scope(function(scope)
      local serving = scope:fork(function() return pcall(app.serve, app) end)
      wait_until(function() return app:local_address() ~= nil end)
      local port = app:local_address().port
      self:assert_true(get(port, "/fast"):find("fast", 1, true) ~= nil) -- it serves
      local client = scope:fork(get, port, "/slow")
      state.started:receive() -- the request is in flight
      local shutdown_done = false
      local shutting = scope:fork(function()
        app:shutdown(30)
        shutdown_done = true
      end)
      wait_until(function() return refused(port) end) -- accepting stopped at once, with a request still being served
      shutdown_returned_early = shutdown_done
      self:assert_false(state.finished)
      state.release:send(true)
      body = client:value()
      shutting:value()
      served_ok = serving:value()
    end)
  end)
  self:assert_false(shutdown_returned_early, "shutdown returned while a request was in flight, before its grace period")
  self:assert_not_nil(body, "the request in flight got its answer")
  self:assert_true(body:find('"done"', 1, true) ~= nil, body)
  self:assert_true(state.finished)
  self:assert_false(state.cancelled)
  self:assert_true(served_ok, "serve returns normally after the shutdown")
  self:assert_nil(app:local_address())
end

function T:test_a_connection_after_the_shutdown_is_refused_and_the_application_is_not_serving()
  local state = slow_application()
  local app = state.app
  local port
  reactor.run(function()
    reactor.scope(function(scope)
      local serving = scope:fork(app.serve, app)
      wait_until(function() return app:local_address() ~= nil end)
      port = app:local_address().port
      app:shutdown(5) -- nothing in flight: returns once the server has stopped
      serving:value()
    end)
    local ok = pcall(net.connect, "127.0.0.1", port)
    self:assert_false(ok, "a connection to the stopped application was accepted")
  end)
  self:assert_nil(app:local_address())
end

function T:test_a_request_that_outlives_the_grace_period_is_cancelled()
  local state = slow_application()
  local app = state.app
  local body
  reactor.run(function()
    reactor.scope(function(scope)
      local serving = scope:fork(app.serve, app)
      wait_until(function() return app:local_address() ~= nil end)
      local client = scope:fork(get, app:local_address().port, "/slow")
      state.started:receive()
      app:shutdown(0.2) -- the action is never released
      body = client:value()
      serving:value()
    end)
  end)
  self:assert_true(state.cancelled, "the action was cancelled when the grace period ended")
  self:assert_false(state.finished)
  self:assert_true(body == nil or body:find('"done"', 1, true) == nil, "no complete answer for a cancelled request")
end

function T:test_requests_in_flight_all_finish_within_the_grace_period()
  local state = slow_application()
  local app = state.app
  local bodies = {}
  reactor.run(function()
    reactor.scope(function(scope)
      local serving = scope:fork(app.serve, app)
      wait_until(function() return app:local_address() ~= nil end)
      local port = app:local_address().port
      local clients = {}
      for index = 1, 4 do clients[index] = scope:fork(get, port, "/slow") end
      for _ = 1, 4 do state.started:receive() end -- all four are being served
      local shutting = scope:fork(app.shutdown, app, 30)
      wait_until(function() return refused(port) end)
      for _ = 1, 4 do state.release:send(true) end
      for index, client in ipairs(clients) do bodies[index] = client:value() end
      shutting:value()
      serving:value()
    end)
  end)
  for index = 1, 4 do
    self:assert_not_nil(bodies[index], "request " .. index)
    self:assert_true(bodies[index]:find('"done"', 1, true) ~= nil, "request " .. index)
  end
  self:assert_false(state.cancelled)
end

return T
