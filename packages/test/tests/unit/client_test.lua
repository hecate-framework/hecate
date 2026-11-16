-- The in-process client: requests served to an action through `http.serve_request`, without a socket.
global <const> require, error

local hecate_test = require("hecate.test")
local http = require("hecate.http")
local core = require("hecate.core")

local T = hecate_test.Case("ClientTest")

-- An action that echoes what it received.
local function echo(request)
  local content = request:read_content()
  return http.Response(200, { content = request.method .. " " .. request.target .. " " .. (request.fields:get("content-type") or "-") .. " " .. content })
end

function T:test_a_request_reaches_the_action_and_the_response_comes_back()
  local client = hecate_test.Client(echo)
  local response, failure = client:get("/users/42?x=1")
  self:assert_equal(200, response.status)
  self:assert_equal("GET /users/42?x=1 - ", response:read_content())
  self:assert_nil(failure)
end

function T:test_json_is_encoded_and_the_content_type_set()
  local client = hecate_test.Client(echo)
  local response = client:post("/items", { json = { name = "a" } })
  self:assert_equal('POST /items application/json {"name":"a"}', response:read_content())
  local custom = client:put("/items", { json = { 1 }, fields = { ["Content-Type"] = "application/vnd.x+json" } })
  self:assert_match("application/vnd%.x%+json", custom:read_content())
end

function T:test_a_raising_action_gives_a_500_and_the_failure()
  local client = hecate_test.Client(function() error(core.Error("boom")) end)
  local response, failure = client:delete("/x")
  self:assert_equal(500, response.status)
  self:assert_true(failure ~= nil)
end

function T:test_bad_use_raises_argument_error()
  local client = hecate_test.Client(echo)
  self:assert_error(function() client:post("/x", { json = 1, content = "y" }) end, { class = core.ArgumentError })
  ---@type any
  local not_a_function = {}
  self:assert_error(function() hecate_test.Client(not_a_function) end, { class = core.ArgumentError })
end

return core.finalise(T)
