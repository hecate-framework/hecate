---@diagnostic disable: missing-fields, param-type-mismatch, need-check-nil  -- the tests pass invalid arguments on purpose
-- Form content through the server and the client: urlencoded and multipart, the status of every refusal, and streaming.
local test = require("harness.test")
local json = require("hecate.json")
local http = require("hecate.http")
local T = test.Case("ServerFormsTest")

local dir = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):gsub("/[^/]*$", "")
local support = dofile(dir .. "/../fixtures/client.lua")
local connect, with_server = support.connect, support.with_server
local Response, Client = http.Response, http.Client

local function url(port, path) return "http://127.0.0.1:" .. port .. (path or "/") end

local function forms_action(options)
  return function(request)
    if request.path == "/urlencoded" then
      local f = request:read_form(options and options.form)
      local pairs_ = {}
      for name, value in f:pairs() do pairs_[#pairs_ + 1] = { name, value } end
      return Response(200, { content = json.encode({ pairs = pairs_ }) })
    end
    local reader = request:stream_parts(options and options.parts)
    local out = {}
    while true do
      local part = reader:next_part()
      if part == nil then break end
      out[#out + 1] = { name = part.name, filename = part.filename, safe = part:safe_filename(), type = part.content_type, content = part:read_content() }
    end
    return Response(200, { content = json.encode({ parts = out }) })
  end
end

function T:test_the_client_sends_urlencoded_pairs_and_the_server_reads_them_back()
  with_server(self, forms_action(), nil, function(port)
    local client <close> = Client()
    local response = client:post(url(port, "/urlencoded"), nil, { form = { { "a", "1" }, { "b", "two words & é" }, { "a", "3" } } })
    local info = json.decode(response:read_content())
    self:assert_equal(3, #info.pairs)
    self:assert_equal("two words & é", info.pairs[2][2])
    self:assert_equal("3", info.pairs[3][2])
  end)
end

function T:test_the_client_sends_multipart_with_a_streamed_file_and_the_server_reads_the_parts()
  with_server(self, forms_action(), nil, function(port)
    local client <close> = Client()
    local response = client:post(url(port, "/multipart"), nil, { multipart = {
      { name = "title", content = "hello" },
      { name = "upload", filename = "../../etc/passwd", content_type = "text/plain", content = function(write) write("line1\r\n"); write("--x\r\nline2") end },
    } })
    local info = json.decode(response:read_content())
    self:assert_equal(2, #info.parts)
    self:assert_equal("hello", info.parts[1].content)
    self:assert_equal("../../etc/passwd", info.parts[2].filename)
    self:assert_equal("passwd", info.parts[2].safe)
    self:assert_equal("text/plain", info.parts[2].type)
    self:assert_equal("line1\r\n--x\r\nline2", info.parts[2].content)
  end)
end

function T:test_content_exclusion_in_the_client()
  with_server(self, forms_action(), nil, function(port)
    local client <close> = Client()
    self:assert_error(function() client:post(url(port), "x", { form = { { "a", "1" } } }) end)
    self:assert_error(function() client:post(url(port), nil, { form = { { "a", "1" } }, multipart = {} }) end)
  end)
end

local function status_of(client, text)
  local response = client:request(text)
  return response.status, response
end

function T:test_refusals_have_their_status_and_echo_nothing_of_the_input()
  with_server(self, forms_action({ form = { max_pairs = 2 }, parts = { max_parts = 2 } }), nil, function(port)
    local function post(path, content_type, content)
      local client <close> = connect(port)
      return status_of(client, ("POST %s HTTP/1.1\r\nHost: t\r\nContent-Type: %s\r\nContent-Length: %d\r\n\r\n%s"):format(path, content_type, #content, content))
    end
    local status, response = post("/urlencoded", "application/json", '{"password":"hunter2"}')
    self:assert_equal(415, status)
    self:assert_nil(response.content:find("hunter2", 1, true))
    self:assert_equal(400, (post("/urlencoded", "application/x-www-form-urlencoded", "password=%zz")))
    self:assert_equal(413, (post("/urlencoded", "application/x-www-form-urlencoded", "a=1&b=2&c=3")))
    self:assert_equal(415, (post("/multipart", "text/plain", "x")))
    self:assert_equal(400, (post("/multipart", "multipart/form-data", "x")), "a missing boundary")
    self:assert_equal(400, (post("/multipart", "multipart/form-data; boundary=" .. ("a"):rep(80), "x")))
    local body = "--b\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\nx\r\n"
    self:assert_equal(400, (post("/multipart", "multipart/form-data; boundary=b", body)), "no final boundary")
    local many = "--b\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\nx\r\n"
    self:assert_equal(413, (post("/multipart", "multipart/form-data; boundary=b", many:rep(3) .. "--b--\r\n")), "max_parts is 2 in this action")
    local healthy <close> = connect(port)
    self:assert_equal(200, (status_of(healthy, "POST /urlencoded HTTP/1.1\r\nHost: t\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: 3\r\n\r\na=1")))
  end)
end

function T:test_a_large_part_is_streamed_in_bounded_chunks_and_content_over_the_server_limit_is_413()
  local largest, total = 0, 0
  with_server(self, function(request)
    local reader = request:stream_parts({ max_part_size = 8 * 1024 * 1024, max_total_size = 8 * 1024 * 1024 })
    local part = reader:next_part()
    local stream = part:stream_content()
    while true do
      local chunk = stream:read()
      if chunk == nil then break end
      largest = math.max(largest, #chunk)
      total = total + #chunk
    end
    return Response(200, { content = tostring(total) })
  end, { max_content = 8 * 1024 * 1024 }, function(port)
    local client <close> = Client()
    local size = 3 * 1024 * 1024
    local response = client:post(url(port), nil, { multipart = { { name = "big", filename = "big.bin", content = function(write)
      local piece = ("x"):rep(64 * 1024)
      for _ = 1, size // #piece do write(piece) end
    end } } })
    self:assert_equal(tostring(size), response:read_content())
    self:assert_true(largest <= 20000, "chunks stay near one read: " .. largest)
  end)
  with_server(self, forms_action(), { max_content = 1000 }, function(port)
    local client <close> = Client()
    local response = client:post(url(port, "/multipart"), nil, { multipart = { { name = "a", content = ("x"):rep(5000) } } })
    self:assert_equal(413, response.status)
    response:close()
  end)
end

return T
