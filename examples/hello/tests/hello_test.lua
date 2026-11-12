---@diagnostic disable: need-check-nil, param-type-mismatch, missing-fields, undefined-field, assign-type-mismatch, inject-field
local test = require("harness.test")
local http = require("hecate.http")
local reactor = require("hecate.reactor")
local log = require("hecate.log")
local hello = require("hello")
local T = test.Case("HelloExampleTest")

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\][^/\\]+$") or "."
local wire = dofile(here .. "/helpers/wire.lua")

--- Boots the application on an ephemeral port, runs `body(base_url)` as a client, then shuts down.
local function with_server(body)
  local app = hello.application({ signals = false, grace_timeout = 1, logger = log.Logger({ sinks = { log.MemorySink() } }), server = { host = "127.0.0.1", port = 0 } })
  reactor.run(function()
    reactor.fork(function()
      reactor.deadline(10, function() while not app:local_address() do reactor.sleep(0.005) end end)
      local base = "http://127.0.0.1:" .. app:local_address().port
      local ok, err = pcall(body, base)
      app:shutdown(1)
      if not ok then error(err, 0) end
    end)
    reactor.deadline(10, app.serve, app)
  end)
end

function T:test_a_name_is_greeted_through_the_response_schema()
  with_server(function(base)
    local response = http.Client():get(base .. "/hello/Ada")
    self:assert_equal(200, response.status)
    self:assert_equal("Hello, Ada!", response:read_json().message)
  end)
end

function T:test_an_invalid_name_is_a_422_problem_with_a_source()
  with_server(function(base)
    local response = http.Client():post(base .. "/greetings", { name = "" })
    self:assert_equal(422, response.status)
    self:assert_equal("application/problem+json", response.fields:get("Content-Type"))
    local problem = response:read_json()
    self:assert_equal("content", problem.errors[1].source)
    self:assert_equal("/name", problem.errors[1].pointer)
    local too_long = http.Client():get(base .. "/hello/" .. ("x"):rep(41))
    local path_problem = too_long:read_json()
    self:assert_equal(422, path_problem.status)
    self:assert_equal("path", path_problem.errors[1].source)
  end)
end

function T:test_a_greeting_is_created_with_201()
  with_server(function(base)
    local response = http.Client():post(base .. "/greetings", { name = "Ada", language = "fr" })
    self:assert_equal(201, response.status)
    local created = response:read_json()
    self:assert_equal("Bonjour, Ada!", created.message)
    self:assert_equal("number", type(created.id))
  end)
end

function T:test_the_health_route_module_answers()
  with_server(function(base)
    local response = http.Client():get(base .. "/health")
    self:assert_equal(200, response.status)
    self:assert_equal("ok", response:read_json().status)
  end)
end

function T:test_an_unknown_path_is_a_404_problem_details_response()
  with_server(function(base)
    local response = http.Client():get(base .. "/nowhere")
    self:assert_equal(404, response.status)
    self:assert_equal("application/problem+json", response.fields:get("Content-Type"))
    self:assert_equal(404, response:read_json().status)
  end)
end

function T:test_shutdown_drains_a_request_in_flight_and_refuses_new_connections()
  local app = hello.application({ signals = false, grace_timeout = 5, logger = log.Logger({ sinks = { log.MemorySink() } }), server = { host = "127.0.0.1", port = 0 } })
  local response, refused, idle_closed, served_ok, err
  reactor.run(function()
    reactor.fork(function()
      local ok, failure = pcall(reactor.deadline, 20, function()
        while not app:local_address() do reactor.sleep(0.005) end
        response, refused, idle_closed = wire.request_in_flight_during_shutdown(reactor, app:local_address().port, 1,
          function() app:shutdown(5) end)
      end)
      if not ok then
        app:shutdown(1)
        error(failure, 0)
      end
    end)
    served_ok, err = pcall(reactor.deadline, 20, app.serve, app)
  end)
  self:assert_true(served_ok, tostring(err))
  self:assert_true(refused, "new connections are refused while the request in flight drains")
  self:assert_true(idle_closed, "the idle connection was closed: the shutdown had begun before the content was sent")
  self:assert_not_nil(response, "the request in flight is answered")
  self:assert_equal(201, response.status)
  self:assert_true(response.body:find('"Hola, Ada!"', 1, true) ~= nil, response.body)
  self:assert_true(response.head:lower():find("\r\nconnection: close", 1, true) ~= nil, response.head)
  self:assert_nil(app:local_address())
end

return T
