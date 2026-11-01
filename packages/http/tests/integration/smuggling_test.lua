---@diagnostic disable: missing-fields, param-type-mismatch, need-check-nil, assign-type-mismatch  -- the tests pass invalid arguments on purpose
-- Request smuggling, end to end: the vectors of the conformance file go through a real server (which must refuse them
-- before any action runs, whatever follows on the connection), and the response-side vectors go through the client's pool.
local test = require("harness.test")
local core = require("hecate.core")
local http = require("hecate.http")
local T = test.Case("SmugglingTest")

local dir = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):gsub("/[^/]*$", "")
local support = dofile(dir .. "/../fixtures/client.lua")
local connect, get, with_server, run, scripted, read_head, ok = support.connect, support.get, support.with_server, support.run,
  support.scripted, support.read_head, support.ok
local Response, Client = http.Response, http.Client

local VECTORS = {
  { "CL.TE", "POST / HTTP/1.1\r\nHost: h\r\nContent-Length: 4\r\nTransfer-Encoding: chunked\r\n\r\n1\r\nZ\r\nQ" },
  { "TE.CL", "POST / HTTP/1.1\r\nHost: h\r\nTransfer-Encoding: chunked\r\nContent-Length: 4\r\n\r\n5c\r\nGPOST / HTTP/1.1\r\n\r\n0\r\n\r\n" },
  { "TE.TE with a space before the colon", "POST / HTTP/1.1\r\nHost: h\r\nTransfer-Encoding : chunked\r\nContent-Length: 4\r\n\r\n0\r\n\r\n" },
  { "TE with a tab and a CL", "POST / HTTP/1.1\r\nHost: h\r\nTransfer-Encoding:\tchunked\r\nContent-Length: 4\r\n\r\n0\r\n\r\n" },
  { "CL.CL", "POST / HTTP/1.1\r\nHost: h\r\nContent-Length: 0\r\nContent-Length: 44\r\n\r\n" },
  { "CL, then a folded CL", "POST / HTTP/1.1\r\nHost: h\r\nContent-Length: 4\r\n Content-Length: 5\r\n\r\nbody" },
  { "bare LF between fields", "POST / HTTP/1.1\r\nHost: h\nContent-Length: 4\r\n\r\nbody" },
  { "chunk size with a bare LF hiding a request", "POST / HTTP/1.1\r\nHost: h\r\nTransfer-Encoding: chunked\r\n\r\n0\nGET /admin HTTP/1.1\r\nHost: h\r\n\r\n" },
  { "chunk extension with a bare CR", "POST / HTTP/1.1\r\nHost: h\r\nTransfer-Encoding: chunked\r\n\r\n2;x=\rab\r\nab\r\n0\r\n\r\n" },
}

local HIDDEN = "GET /hidden HTTP/1.1\r\nHost: h\r\n\r\n"

function T:test_every_vector_is_a_400_with_close_and_no_action_runs_for_it_or_for_what_hides_behind_it()
  local paths = {}
  with_server(self, function(request)
    paths[#paths + 1] = request.path
    request:read_content()
    return Response(200, { content = "ok" })
  end, nil, function(port)
    for _, vector in ipairs(VECTORS) do
      local client <close> = connect(port)
      client:send(vector[2] .. HIDDEN)
      local response = client:read_response()
      self:assert_equal(400, response.status, vector[1])
      self:assert_equal("close", response.fields:get("Connection"), vector[1])
      self:assert_nil(client:read_response(), vector[1] .. ": the connection is closed, nothing else is answered")
    end
    self:assert_equal(0, #paths, "no action ran: " .. table.concat(paths, ","))
    local healthy <close> = connect(port)
    self:assert_equal(200, healthy:request(get("/health")).status)
    self:assert_equal(1, #paths)
  end)
end

function T:test_a_legitimate_request_followed_by_a_smuggled_one_runs_only_the_first()
  local paths = {}
  with_server(self, function(request)
    paths[#paths + 1] = request.path
    return Response(200, { content = "ok" })
  end, nil, function(port)
    local client <close> = connect(port)
    client:send("GET /first HTTP/1.1\r\nHost: h\r\n\r\n" .. VECTORS[1][2] .. HIDDEN)
    self:assert_equal(200, client:read_response().status)
    self:assert_equal(400, client:read_response().status)
    self:assert_nil(client:read_response())
    self:assert_equal(1, #paths)
    self:assert_equal("/first", paths[1])
  end)
end

-- Responses ---------------------------------------------------------------------------------------------------------

--- A server whose first connection answers the first request normally and the second with `second`; later connections
--- answer normally. Returns the state (with `accepted`).
local function poisoned(second)
  return scripted(function(stream, index)
    if index == 1 then
      read_head(stream)
      stream:write(ok("one"))
      read_head(stream)
      stream:write(second)
      read_head(stream) -- a third request on this connection would be a defect
      return
    end
    while read_head(stream) do stream:write(ok("fresh")) end
  end)
end

local function url(server) return "http://127.0.0.1:" .. server.port .. "/" end

function T:test_a_response_with_content_length_and_transfer_encoding_is_refused_and_the_connection_dropped()
  run(self, function()
    local server = poisoned("HTTP/1.1 200 OK\r\nContent-Length: 3\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n")
    local client <close> = Client()
    client:get(url(server)):read_content()
    local err = self:assert_error(function() client:get(url(server)) end)
    self:assert_true(core.is_instance_of(err, http.ParseError), tostring(err))
    self:assert_equal("fresh", client:get(url(server)):read_content(), "the next request opens a new connection")
    self:assert_equal(2, server.accepted)
    server.stop()
  end)
end

function T:test_a_response_with_two_content_lengths_is_refused()
  run(self, function()
    local server = poisoned("HTTP/1.1 200 OK\r\nContent-Length: 3\r\nContent-Length: 5\r\n\r\nabcde")
    local client <close> = Client()
    client:get(url(server)):read_content()
    local err = self:assert_error(function() client:get(url(server)) end)
    self:assert_true(core.is_instance_of(err, http.ParseError), tostring(err))
    self:assert_equal("fresh", client:get(url(server)):read_content())
    self:assert_equal(2, server.accepted)
    server.stop()
  end)
end

function T:test_a_bad_chunk_size_on_a_pooled_connection_drops_the_connection()
  run(self, function()
    local server = poisoned("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nZZ\r\nabc\r\n0\r\n\r\n")
    local client <close> = Client()
    client:get(url(server)):read_content()
    local response_err = self:assert_error(function() return client:get(url(server)):read_content() end)
    self:assert_true(core.is_instance_of(response_err, http.ParseError), tostring(response_err))
    self:assert_equal("fresh", client:get(url(server)):read_content())
    self:assert_equal(2, server.accepted, "the poisoned connection was not reused")
    server.stop()
  end)
end

function T:test_bytes_beyond_the_content_length_do_not_poison_the_next_request()
  run(self, function()
    local server = scripted(function(stream, index)
      while read_head(stream) do
        if index == 1 then
          stream:write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nokHTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nPOISON")
        else
          stream:write(ok("clean"))
        end
      end
    end)
    local client <close> = Client()
    self:assert_equal("ok", client:get(url(server)):read_content())
    self:assert_equal("clean", client:get(url(server)):read_content(), "the second request is answered by its own response")
    self:assert_equal(2, server.accepted, "the connection with extra bytes was not pooled")
    server.stop()
  end)
end

return T
