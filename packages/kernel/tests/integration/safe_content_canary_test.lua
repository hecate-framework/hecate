---@diagnostic disable: need-check-nil, undefined-field, param-type-mismatch, missing-fields, assign-type-mismatch
-- Safe content canary (OQ-111, CWE-532; phase gates, "Safe content"). One canary string is put through every way a
-- value can reach an output of the framework: an error raised in an action, the fields of a log record, a secret key of
-- the configuration, and request inputs that are refused (content, a header field, a cookie, the query, a malformed
-- head). Every output is then searched for it: the log records (in memory, and as rendered by the JSON lines and the
-- console sinks), the problem details responses with the default `errors.expose_details = false`, the messages of the
-- errors a caller receives, and the bytes a client reads from the socket.
--
-- Where the canary is expected to appear, by a documented rule, the test asserts that rule instead of its absence:
-- the message of an unhandled action error is logged as it is (OQ-111 (3)), a free-text log field is not scanned,
-- `errors.expose_details = true` forwards the text of a 500 in `debug`, and `on_response` receives the request target
-- with its query (before-going-to-production.md, "The access log").
local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local http = require("hecate.http")
local log = require("hecate.log")
local schema = require("hecate.schema")
local kernel = require("hecate.kernel")
local T = test.Case("SafeContentCanaryTest")

local CANARY <const> = "CANARY-7f3a9c"

--- Whether `text` holds the canary.
---@param text any
---@return boolean
local function has_canary(text)
  return type(text) == "string" and text:find(CANARY, 1, true) ~= nil
end

--- Every string reachable from `value`, keys included, appended to `out`. A table with a metatable (a `Secret`, an
--- error, an instance) contributes its `tostring` only: that is what a sink renders of it; its raw fields are not walked.
---@param value any
---@param out string[]
---@param seen? table
---@return string[]
local function texts(value, out, seen)
  seen = seen or {}
  local kind = type(value)
  if kind == "string" then
    out[#out + 1] = value
  elseif kind == "table" then
    if getmetatable(value) ~= nil then
      out[#out + 1] = tostring(value)
    elseif not seen[value] then
      seen[value] = true
      for key, item in pairs(value) do
        texts(key, out, seen)
        texts(item, out, seen)
      end
    end
  elseif value ~= nil then
    out[#out + 1] = tostring(value)
  end
  return out
end

--- The texts of `value` that hold the canary, joined (empty when none): the message of a failed assertion.
---@param value any
---@return string
local function canary_in(value)
  local found = {}
  for _, text in ipairs(texts(value, {})) do
    if has_canary(text) then found[#found + 1] = text end
  end
  return table.concat(found, " | ")
end

--- The outputs of the application logger: the records kept in memory and the lines rendered by the JSON lines and the
--- console sinks (the renderings of the `json_lines`, `file` and `console` values of `logging.sinks`).
---@class CanaryCapture
---@field memory hecate.log.MemorySink
---@field json_lines string[]
---@field console string[]

--- Adds the capturing sinks to `logger`.
---@param logger hecate.log.Logger
---@return CanaryCapture
local function capture(logger)
  local captured = { memory = log.MemorySink(), json_lines = {}, console = {} }
  logger:add_sink(captured.memory)
  logger:add_sink(log.JsonLinesSink({ output = function(line) captured.json_lines[#captured.json_lines + 1] = line end }))
  logger:add_sink(log.ConsoleSink({ output = function(line) captured.console[#captured.console + 1] = line end }))
  return captured
end

--- Every captured log output, as texts.
---@param captured CanaryCapture
---@return string[]
local function log_texts(captured)
  local out = {}
  for _, record in ipairs(captured.memory:records()) do
    out[#out + 1] = record.message
    texts(record.fields, out)
    texts(record.context, out)
  end
  for _, line in ipairs(captured.json_lines) do out[#out + 1] = line end
  for _, line in ipairs(captured.console) do out[#out + 1] = line end
  return out
end

--- The captured log outputs that hold the canary, joined (empty when none).
---@param captured CanaryCapture
---@return string
local function canary_in_logs(captured)
  local found = {}
  for _, text in ipairs(log_texts(captured)) do
    if has_canary(text) then found[#found + 1] = text end
  end
  return table.concat(found, " | ")
end

--- The first memory record whose message is `message`, or nil.
---@param captured CanaryCapture
---@param message string
---@return hecate.log.Record?
local function record_of(captured, message)
  for _, record in ipairs(captured.memory:records()) do
    if record.message == message then return record end
  end
  return nil
end

--- Everything a client reads of an in-process response: the status line data, the fields and the content.
---@param response hecate.http.Response
---@return string
local function response_text(response)
  local parts = { tostring(response.status) }
  for name, value in response.fields:lines() do parts[#parts + 1] = name .. ": " .. value end
  local content = response.content
  if type(content) == "string" then parts[#parts + 1] = content end
  return table.concat(parts, "\n")
end

local PROPERTIES <const> = {
  database = schema.object({ password = schema.string(), port = schema.default(schema.integer(), 5432) }),
  api = schema.optional(schema.object({ key = schema.optional(schema.string({ pattern = "^[0-9]+$" })) })),
}

--- Loads a configuration in `environment` from `env` (environment variables): `database.password` and `api.key` are
--- secret keys; the environment file empties `logging.sinks` (no output to the standard output during the test) and adds
--- `national_id` to `logging.redact`.
---@param env table<string, string>
---@param environment? string  default `production`
---@return hecate.config.Configuration
local function configuration(env, environment)
  environment = environment or "production"
  return kernel.load_configuration({
    properties = PROPERTIES, environment = environment, secrets = { "database.password", "api.key" },
    getenv = function(name) return env[name] end,
    read_file = function(path)
      if path == "config/" .. environment .. ".lua" then
        return "return { logging = { sinks = {}, redact = { \"national_id\" } } }"
      end
      return nil, "no such file: " .. path, true
    end,
  })
end

--- The routes of the canary application. `/log` logs the canary in fields; `/secret` logs the secret configuration
--- value; `/fail` raises an error whose message holds the canary; `/fail-object` raises an error that holds it only in
--- its context; `/fail-cause` one that holds it only in the message of its cause; `/unencodable` raises a problem whose extension cannot be encoded; `/users` declares
--- inputs of every location.
---@param loaded hecate.config.Configuration
---@return hecate.kernel.RouteModule
local function canary_routes(loaded)
  local routes = kernel.routes("canary")
  routes:post("/users", {
    parameters = {
      query = { limit = schema.optional(schema.integer()) },
      fields = { ["X-Page"] = schema.optional(schema.integer()) },
      cookies = { session_id = schema.optional(schema.integer()) },
    },
    content = { ["application/json"] = schema.object({
      email = schema.string({ format = "email" }),
      age = schema.integer({ minimum = 0 }),
      role = schema.enumeration({ "reader", "writer" }),
      nickname = schema.optional(schema.string({ max_length = 4 })),
    }) },
    action = function() return { created = true } end,
  })
  routes:get("/log", { action = function()
    log.default():warning("login attempt", {
      password = CANARY, Authorization = "Bearer " .. CANARY, headers = { cookie = "sid=" .. CANARY },
      national_id = CANARY, -- added by `logging.redact`
      note = "free text with " .. CANARY, -- a name that is not in the list: not redacted, by design (OQ-111 (3))
    })
    return { logged = true }
  end })
  routes:get("/secret", { action = function()
    -- Logged under a name that is not in the list: only the secret object keeps it out of the output.
    log.default():informational("connecting", { database_credential = loaded:get("database.password") })
    return { connected = true }
  end })
  -- The query parameter is declared: with `requests.inputs = "strict"` an undeclared one would be refused with a 422.
  local query = { access_token = schema.optional(schema.string()) }
  routes:get("/fail", { parameters = { query = query }, action = function()
    error("cannot connect with password " .. CANARY)
  end })
  routes:get("/fail-object", { parameters = { query = query }, action = function()
    error(core.Error({ message = "the lookup failed", context = { password = CANARY, email = CANARY } }))
  end })
  routes:get("/fail-cause", { action = function()
    error(core.Error({ message = "the lookup failed", cause = core.Error({ message = "driver said " .. CANARY }) }))
  end })
  routes:get("/unencodable", { action = function()
    error(kernel.problem.Conflict({ extensions = { info = { [CANARY] = function() end } } }))
  end })
  return routes
end

--- Boots the canary application on `loaded` and captures the outputs of the logger the configuration built.
---@param loaded hecate.config.Configuration
---@param options? table  more options of `Application`
---@return fun(request: hecate.http.Request): hecate.http.Response serve
---@return CanaryCapture captured
---@return hecate.kernel.Application app
local function boot(loaded, options)
  local all = { configuration = loaded, routes = { canary_routes(loaded) }, signals = false }
  for key, value in pairs(options or {}) do all[key] = value end
  local app = kernel.Application(all)
  local serve = app:boot()
  -- The logger built from `logging.*` became the default logger at boot: it is the one the actions above use.
  return serve, capture(log.default()), app
end

local function request(method, target, options)
  options = options or {}
  local fields = http.Fields(options.fields)
  if options.content ~= nil then fields:set("Content-Type", "application/json") end
  return http.Request({ method = method, target = target, fields = fields, content = options.content })
end

function T:tear_down()
  log.set_default(nil)
end

-- (c) A configuration value declared secret --------------------------------------------------------------------------

function T:test_a_secret_configuration_value_is_never_rendered()
  local loaded = configuration({ HECATE_DATABASE__PASSWORD = CANARY })
  local value = loaded:get("database.password")
  self:assert_true(core.is_instance_of(value, log.Secret), "kernel.load_configuration wraps with hecate.log.Secret")
  self:assert_equal(CANARY, value:reveal())
  self:assert_false(has_canary(tostring(value)))
  self:assert_false(has_canary(loaded:describe()), loaded:describe())
  local serve, captured = boot(loaded)
  self:assert_equal(200, serve(request("GET", "/secret")).status)
  local record = record_of(captured, "connecting")
  self:assert_not_nil(record)
  -- The memory sink keeps the secret object (logging.md, "Secrets and privacy"); the renderings never reveal it.
  self:assert_true(core.is_instance_of(record.fields.database_credential, log.Secret))
  self:assert_equal("", canary_in_logs(captured))
  self:assert_true(captured.json_lines[#captured.json_lines]:find("[redacted]", 1, true) ~= nil)
  self:assert_true(captured.console[#captured.console]:find("[redacted]", 1, true) ~= nil)
end

function T:test_an_invalid_configuration_value_is_not_quoted()
  -- A secret key, a key that is not secret, and a key that is not declared: the error names each, never its value.
  local ok, err = pcall(configuration, {
    HECATE_DATABASE__PASSWORD = "x", HECATE_DATABASE__PORT = CANARY, HECATE_API__KEY = CANARY,
  })
  self:assert_false(ok)
  self:assert_true(core.is_instance_of(err, core.ConfigurationError), tostring(err))
  self:assert_false(has_canary(tostring(err)), tostring(err))
  self:assert_equal("", canary_in(err.context))
  -- A syntax error of a configuration file: the `near '...'` fragment, which quotes the file, is cut.
  local syntax_ok, syntax_err = pcall(kernel.load_configuration, {
    properties = PROPERTIES, environment = "production", getenv = function() return nil end,
    read_file = function(path)
      if path == "config/production.lua" then return "return { database = { password = \"" .. CANARY .. "\" \"x\" } }" end
      return nil, "no such file: " .. path, true
    end,
  })
  self:assert_false(syntax_ok)
  self:assert_false(has_canary(tostring(syntax_err)), tostring(syntax_err))
end

-- (b) Log fields -----------------------------------------------------------------------------------------------------

function T:test_log_fields_are_redacted_by_name_and_free_text_is_not_scanned()
  local serve, captured = boot(configuration({ HECATE_DATABASE__PASSWORD = "x" }))
  self:assert_equal(200, serve(request("GET", "/log")).status)
  local record = record_of(captured, "login attempt")
  self:assert_not_nil(record)
  local fields = record.fields
  -- log.DEFAULT_REDACT, case-insensitive, at any depth of a plain table; `national_id` comes from logging.redact.
  self:assert_true(core.is_instance_of(fields.password, log.Secret))
  self:assert_true(core.is_instance_of(fields.Authorization, log.Secret))
  self:assert_true(core.is_instance_of(fields.headers.cookie, log.Secret))
  self:assert_true(core.is_instance_of(fields.national_id, log.Secret))
  -- Documented behaviour (OQ-111 (3); before-going-to-production.md, "Redaction does not read free text"): a field
  -- whose name is not in the list is written as it is. It is the only place the canary may appear.
  self:assert_true(has_canary(fields.note))
  for _, line in ipairs(captured.json_lines) do
    local decoded = json.decode(line)
    if decoded.message == "login attempt" then
      self:assert_equal("[redacted]", decoded.fields.password)
      self:assert_equal("[redacted]", decoded.fields.Authorization)
      self:assert_equal("[redacted]", decoded.fields.headers.cookie)
      self:assert_equal("[redacted]", decoded.fields.national_id)
      self:assert_true(has_canary(decoded.fields.note))
      decoded.fields.note = nil
      self:assert_equal("", canary_in(decoded))
    end
  end
  for _, line in ipairs(captured.console) do
    if line:find("login attempt", 1, true) then
      -- Only the `note` pair carries it: strip it and nothing is left.
      local without_note = line:gsub("note=\"[^\"]*\"", "")
      self:assert_false(has_canary(without_note), line)
    end
  end
end

-- (a) An error raised in an action -------------------------------------------------------------------------------------

function T:test_an_action_error_reaches_the_log_by_design_but_never_the_client()
  local serve, captured = boot(configuration({ HECATE_DATABASE__PASSWORD = "x" }))
  local response = serve(request("GET", "/fail?access_token=" .. CANARY, { fields = { Authorization = "Bearer " .. CANARY } }))
  self:assert_equal(500, response.status)
  self:assert_false(has_canary(response_text(response)), response_text(response))
  local body = json.decode(response.content)
  self:assert_nil(body.debug, "no debug member while errors.expose_details is false")
  local record = record_of(captured, "unhandled error while serving a request")
  self:assert_not_nil(record)
  -- Documented behaviour (OQ-111 (3)): the message of an unhandled error is logged as it is, in `error` (and in the
  -- traceback, which starts with it). The path is logged without its query, and no request field is logged.
  self:assert_true(has_canary(record.fields.error))
  self:assert_equal("/fail", record.fields.path)
  local others = {}
  for key, value in pairs(record.fields) do
    if key ~= "error" and key ~= "traceback" then others[key] = value end
  end
  self:assert_equal("", canary_in(others))
  self:assert_equal("", canary_in(record.context))
end

function T:test_the_context_of_an_action_error_is_neither_logged_nor_answered()
  local serve, captured = boot(configuration({ HECATE_DATABASE__PASSWORD = "x" }))
  local response = serve(request("GET", "/fail-object"))
  self:assert_equal(500, response.status)
  self:assert_false(has_canary(response_text(response)), response_text(response))
  self:assert_not_nil(record_of(captured, "unhandled error while serving a request"))
  self:assert_equal("", canary_in_logs(captured))
end

function T:test_the_cause_of_an_action_error_reaches_only_the_traceback_field()
  local serve, captured = boot(configuration({ HECATE_DATABASE__PASSWORD = "x" }))
  local response = serve(request("GET", "/fail-cause"))
  self:assert_equal(500, response.status)
  self:assert_false(has_canary(response_text(response)), response_text(response))
  local record = record_of(captured, "unhandled error while serving a request")
  self:assert_not_nil(record)
  -- The `error` field holds the message of the error alone, without its cause.
  self:assert_equal("the lookup failed", record.fields.error)
  -- Documented in website/en/how-to/before-going-to-production.md (Logging): `problems.guard` takes the traceback with
  -- `debug.traceback(tostring(err), 2)`, and `tostring` of a `hecate.core.Error` renders the whole cause chain, so the
  -- `traceback` field starts with the message of the error and of each cause (a driver error, a `DETAIL` text). OQ-111
  -- (3) covers it: an error message must not embed a secret, causes included.
  self:assert_true(has_canary(record.fields.traceback), "the cause chain is in the traceback field")
  self:assert_equal(1, (record.fields.traceback:find("hecate.core.Error: the lookup failed\ncaused by: hecate.core.Error: driver said " .. CANARY, 1, true)),
    "the traceback starts with the message of the error, then its causes")
  local others = {}
  for key, value in pairs(record.fields) do
    if key ~= "traceback" then others[key] = value end
  end
  self:assert_equal("", canary_in(others))
end

function T:test_an_unencodable_problem_logs_no_value()
  local serve, captured = boot(configuration({ HECATE_DATABASE__PASSWORD = "x" }))
  local response = serve(request("GET", "/unencodable"))
  self:assert_equal(500, response.status)
  self:assert_false(has_canary(response_text(response)), response_text(response))
  self:assert_equal("", canary_in_logs(captured))
end

-- (d) Refused request inputs ---------------------------------------------------------------------------------------------

function T:test_refused_inputs_are_never_echoed_nor_logged()
  local serve, captured = boot(configuration({ HECATE_DATABASE__PASSWORD = "x" }))
  local valid = '{"email":"a@example.org","age":1,"role":"reader"}'
  local cases = {
    -- invalid content: a format, a type, an enumeration and a length, each with the canary as the value
    { 422, request("POST", "/users", { content = json.encode({ email = CANARY, age = CANARY, role = CANARY, nickname = CANARY }) }) },
    -- content that is not JSON
    { 400, request("POST", "/users", { content = '{"email":"' .. CANARY }) },
    -- a declared header field, a declared cookie and a declared query parameter that do not coerce
    { 422, request("POST", "/users", { content = valid, fields = { ["X-Page"] = CANARY } }) },
    { 422, request("POST", "/users", { content = valid, fields = { Cookie = "session_id=" .. CANARY } }) },
    { 422, request("POST", "/users?limit=" .. CANARY, { content = valid }) },
    -- an undeclared query parameter (`requests.inputs = "strict"`): named, never its value
    { 422, request("POST", "/users?access_token=" .. CANARY, { content = valid }) },
    -- a media type other than application/json
    { 415, http.Request({ method = "POST", target = "/users", content = CANARY,
      fields = http.Fields({ ["Content-Type"] = "text/plain" }) }) },
  }
  for index, case in ipairs(cases) do
    local response = serve(case[2])
    self:assert_equal(case[1], response.status, "case " .. index)
    self:assert_false(has_canary(response_text(response)), "case " .. index .. ": " .. response_text(response))
  end
  local undeclared = json.decode(serve(request("POST", "/users?access_token=" .. CANARY, { content = valid })).content)
  self:assert_equal("/access_token", undeclared.errors[1].pointer)
  self:assert_nil(undeclared.errors[1].message, "no message while errors.expose_details is false")
  -- Documented in website/en/how-to/before-going-to-production.md (Logging): an input refusal (422, 400, 415) is
  -- returned, not raised, so it is a normal answer: no record at all, so nothing can leak there.
  self:assert_equal(0, #captured.memory:records())
  self:assert_equal("", canary_in_logs(captured))
  -- A header value the message model refuses (a control character): the error names the rule, never the value.
  local ok, err = pcall(http.Fields, { ["X-Token"] = CANARY .. "\1" })
  self:assert_false(ok)
  self:assert_false(has_canary(tostring(err)), tostring(err))
end

function T:test_expose_details_forwards_only_the_documented_members()
  local serve, captured = boot(configuration({ HECATE_DATABASE__PASSWORD = "x", HECATE_ERRORS__EXPOSE_DETAILS = "true" }, "development"))
  -- 422 entries carry the message of each violation: a schema message never quotes the value.
  local invalid = serve(request("POST", "/users", { content = json.encode({ email = CANARY, age = CANARY, role = CANARY, nickname = CANARY }) }))
  self:assert_equal(422, invalid.status)
  local body = json.decode(invalid.content)
  self:assert_not_nil(body.errors[1].message, "errors.expose_details forwards the messages")
  self:assert_false(has_canary(invalid.content), invalid.content)
  -- Documented behaviour (before-going-to-production.md, "Error details"): a 500 carries `debug` with the message of
  -- the error, the canary included. This is why the key must stay false in production.
  local failed = serve(request("GET", "/fail"))
  self:assert_equal(500, failed.status)
  local debug_member = json.decode(failed.content).debug
  self:assert_not_nil(debug_member)
  self:assert_true(has_canary(debug_member.message))
  -- The context of an error is never forwarded, even with the key.
  local object = json.decode(serve(request("GET", "/fail-object")).content).debug
  self:assert_not_nil(object)
  self:assert_equal("", canary_in(object))
  -- Documented in before-going-to-production.md (Error details): the cause chain is part of `tostring`, hence of
  -- `debug.message`, which holds the message of the error and of its causes.
  local caused = json.decode(serve(request("GET", "/fail-cause")).content).debug
  self:assert_not_nil(caused)
  self:assert_true(caused.message:find("the lookup failed", 1, true) ~= nil, caused.message)
  self:assert_true(has_canary(caused.message), "the cause chain is part of the text of the error")
  self:assert_true(log.default() ~= nil and #captured.memory:records() > 0)
end

-- Over a socket: the server refuses a malformed head, and a failing request with credentials in the target and fields --

--- Sends `bytes` on a new connection to `port` and returns everything the server answers until it closes.
---@async
---@param port integer
---@param bytes string
---@return string
local function exchange(port, bytes)
  local net = require("hecate.net")
  local stream = net.connect("127.0.0.1", port)
  stream:write(bytes)
  local parts = {}
  while true do
    local ok, data = pcall(stream.read, stream)
    if not ok or data == nil then break end
    parts[#parts + 1] = data
  end
  stream:close()
  return table.concat(parts)
end

function T:test_over_a_socket_nothing_of_the_request_is_echoed_or_logged()
  local available, why = http.available()
  if not available then
    io.stderr:write("# SKIP: ", tostring(why), "\n")
    return
  end
  local reactor = require("hecate.reactor")
  local targets = {}
  local serve_bytes = false
  local loaded = configuration({ HECATE_DATABASE__PASSWORD = "x" })
  local app = kernel.Application({
    configuration = loaded, routes = { canary_routes(loaded) }, signals = false,
    server = { host = "127.0.0.1", port = 0, on_response = function(info) targets[#targets + 1] = info.target end },
  })
  app:boot()
  local captured = capture(log.default())
  local malformed, failing
  reactor.run(function()
    reactor.scope(function(scope)
      local serving = scope:fork(function() return pcall(app.serve, app) end)
      reactor.deadline(20, function()
        while app:local_address() == nil do reactor.sleep(0.005) end
      end)
      local port = app:local_address().port
      -- A control character in a field value: llhttp refuses the head, the server answers 400 before any action.
      malformed = exchange(port, "GET /log HTTP/1.1\r\nHost: x\r\nX-Token: " .. CANARY .. "\1\r\nConnection: close\r\n\r\n")
      failing = exchange(port, "GET /fail-object?access_token=" .. CANARY .. " HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer "
        .. CANARY .. "\r\nCookie: session=" .. CANARY .. "\r\nConnection: close\r\n\r\n")
      serve_bytes = true
      app:shutdown(1)
      serving:value()
    end)
  end)
  self:assert_true(serve_bytes)
  self:assert_true(malformed:find("^HTTP/1.1 400") ~= nil, malformed)
  self:assert_false(has_canary(malformed), malformed)
  self:assert_true(failing:find("^HTTP/1.1 500") ~= nil, failing)
  self:assert_false(has_canary(failing), failing)
  self:assert_equal("", canary_in_logs(captured))
  -- Documented behaviour (before-going-to-production.md, "The access log"): `on_response` receives the target as
  -- received, query included; stripping it is the job of the hook.
  local with_query = false
  for _, target in ipairs(targets) do with_query = with_query or has_canary(target) end
  self:assert_true(with_query, "on_response receives the query of the target")
end

return T
