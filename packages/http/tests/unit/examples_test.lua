-- The examples included in the website pages are tested files: each one runs without error, and what a line
-- prints is written in a `-- Prints:` block directly under that line (the shared runner
-- `tools/harness/examples.lua`; `docs/architecture/documentation.md`, "Code examples"). A server example that never
-- returns says what it answers instead (`-- Answers: <text>`).
local test = require("harness.test")
local examples = require("harness.examples")
local T = test.Case("ExamplesTest")

local here = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
local directory = here:match("^(.*)/tests/unit/") .. "/examples"
local NAMES = {
  "hecate.http.Server", "hecate.http.Client", "hecate.http.Request.read_form", "hecate.http.Request.stream_parts",
  "hecate.http.Server.limits", "hecate.http.Response.stream", "hecate.http.Server.shutdown", "hecate.http.Client.json",
  "hecate.http.Server.hello", "hecate.http.Server.tls",
}

--- Runs a server example that never returns by itself (`-- Answers: <text>`): the server is created on a free port, one
--- request is sent to it, its answer must be the text, and the server is shut down.
local function run_serving(self, path, source, expected)
  local reactor = require("hecate.reactor")
  local http = require("hecate.http")
  local captured
  local patched_http = setmetatable({ Server = function(action, options)
    options = options or {}
    local copy = {}
    for key, value in pairs(options) do copy[key] = value end
    copy.port = 0 -- a test never binds a fixed port
    captured = http.Server(action, copy)
    return captured
  end }, { __index = http })
  local answer
  local patched_reactor = setmetatable({ run = function(fn)
    return reactor.run(function()
      local main = reactor.fork(fn)
      while captured == nil or captured:local_address() == nil do reactor.sleep(0) end
      local client <close> = http.Client()
      answer = client:get("http://127.0.0.1:" .. captured:local_address().port .. "/"):read_content()
      captured:shutdown(1)
      main:value()
    end)
  end }, { __index = reactor })
  local environment = setmetatable({ require = function(name)
    if name == "hecate.http" then return patched_http end
    if name == "hecate.reactor" then return patched_reactor end
    return require(name)
  end }, { __index = _G })
  assert(load(source, "@" .. path, "t", environment))()
  self:assert_equal(expected, (answer:gsub("\n$", "")), path)
end

function T:test_every_example_runs_and_prints_what_it_says()
  local net = require("hecate.net")
  local problems = {}
  for _, name in ipairs(NAMES) do
    local path = ("%s/%s.lua"):format(directory, name)
    local file = assert(io.open(path, "rb"))
    local source = file:read("a")
    file:close()
    local skip = name:find("tls$") and not net.tls.available()
    if skip then
      -- same rule as the TLS tests: fail on CI unless the job opts out (HECATE_REQUIRE_TLS=0, the sanitizer job)
      local required = os.getenv("HECATE_REQUIRE_TLS")
      if required == "1" or (required ~= "0" and os.getenv("CI")) then self:fail(path .. " needs the TLS module") end
      print("# SKIP " .. name .. ": the TLS module is not built")
    elseif source:match("\n%-%- Answers: ") then
      run_serving(self, path, source, source:match("\n%-%- Answers: ([^\n]*)"))
    else
      local problem = examples.run(path)
      problems[#problems + 1] = problem
    end
  end
  if #problems > 0 then self:fail(table.concat(problems, "\n")) end
end

return T
