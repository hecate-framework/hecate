-- End to end, on the platform that runs it: the built `hecate` executable creates a project, runs its tests, exports and
-- lints its contract, generates its unit, serves it and answers a request; the example `hello` is a project that
-- `hecate test` and `hecate contract` handle. The packages of the repository stand in for the rocks that are not
-- published yet (`link-modules`). Skipped where there is no Lua to link (the build task says why).
local test = require("harness.test")
local util = require("lib.util")
local T = test.Case("CliEndToEndTest")

local windows = util.is_windows()
local executable -- the built executable, once

--- Builds the executable once for this file; nil when the platform has nothing to link.
local function built()
  if executable ~= nil then return executable or nil end
  local dir = ".hecate/build/cli-e2e"
  local out = dir .. "/hecate" .. (windows and ".exe" or "")
  local log, ok = util.capture(("%s tools/run.lua build-cli --output=%s 2>&1"):format(util.quote(util.interpreter()), out))
  if not ok and log:find("no Lua 5.5 with", 1, true) then executable = false return nil end
  assert(ok, log)
  executable = out
  return out
end

--- The command that runs `command` (arguments after the executable) in `directory`.
local function in_directory(directory, exe, command)
  local cd = windows and "cd /d " or "cd "
  return ("%s%s && %s %s 2>&1"):format(cd, util.quote(directory), util.quote(exe), command)
end

--- The absolute path of a repository-relative path (the commands change directory).
local function absolute(path)
  local cwd = util.capture(windows and "cd" or "pwd"):gsub("\\", "/")
  return cwd .. "/" .. path
end

--- A free TCP port of the loopback interface (the system picks it), nil when luv cannot be loaded.
local function free_port()
  local loaded, uv = pcall(require, "luv")
  if not loaded then return nil end
  local tcp = uv.new_tcp()
  tcp:bind("127.0.0.1", 0)
  local port = tcp:getsockname().port
  tcp:close()
  return port
end

--- A progress line of the serve test, shown in the log of the run (a hang on Windows shows where it stopped).
local function progress(text)
  io.stdout:write("  # serve: ", text, "\n")
  io.stdout:flush()
end

--- Stops a server and what it started: on Windows `kill` ends only the supervisor (TerminateProcess), and the child
--- would keep the port and lock the executable, so the whole tree is ended.
local function stop_tree(server)
  if windows then os.execute(("taskkill /T /F /PID %d >nul 2>&1"):format(server.pid)) else server:kill() end
  server:wait()
end

--- Copies the content of `from` into `to` (created).
local function copy_tree(from, to)
  util.mkdir(to)
  local cmd = windows and ("xcopy /E /I /Y /Q %s %s >NUL"):format(util.quote(from), util.quote(to))
    or ("cp -R %s/. %s/"):format(util.quote(from), util.quote(to))
  return os.execute(cmd) == true
end

--- Runs `body`, removes `directory` whatever happens, then re-raises what `body` raised.
local function with_cleanup(directory, body)
  local ok, err = pcall(body)
  util.remove_tree(directory)
  if not ok then error(err, 0) end
end

--- Creates a project `shop` in a temporary directory (linked to the packages of the repository), runs `body(run, project, base,
--- exe)` and removes the directory whatever happens. Each test of this file does it for itself: the watchdog of the harness
--- gives every test its own time, and a Windows process start is slow.
local function with_project(self, body)
  local exe = built()
  if not exe then return end
  exe = absolute(exe)
  local base = util.make_temp_dir(".hecate", "e2e")
  assert(base)
  base = absolute(base)
  with_cleanup(base, function()
    local function run(command, directory) return util.capture(in_directory(directory or base, exe, command)) end
    local out, ok = run("new shop")
    self:assert_true(ok, out)
    local project = base .. "/shop"
    local linked, linked_ok = util.capture(("%s tools/run.lua link-modules %s 2>&1"):format(util.quote(util.interpreter()), util.quote(project)))
    self:assert_true(linked_ok, linked)
    body(run, project, base, exe)
  end)
end

function T:test_a_new_project_runs_its_tests_in_the_process_and_with_workers()
  with_project(self, function(run, project, base)
    local out, ok = run("test", project)
    self:assert_true(ok, out)
    self:assert_true(out:find("4 passed", 1, true) ~= nil, out)

    out, ok = run("test --jobs=2", project)
    self:assert_true(ok, out)
    self:assert_true(out:find("4 passed", 1, true) ~= nil, out)

    out, ok = run("test --filter=no_such_test_exists", project)
    self:assert_true(ok, out) -- a selection that matches nothing is a warning (hecate.test: `ok` stays true), not a failure
    self:assert_true(out:find("no test matches the selection", 1, true) ~= nil, out)

    -- A project without a manifest says what to do.
    local empty = base .. "/empty"
    util.mkdir(empty)
    out, ok = run("test", empty)
    self:assert_false(ok, out)
    self:assert_true(out:find("hecate new", 1, true) ~= nil, out)

    -- A failing test makes the run fail and is reported, in the process and with workers.
    local failing = assert(io.open(project .. "/tests/failing_test.lua", "wb"))
    failing:write('local test = require("hecate.test")\nlocal T = test.Case("FailingTest")\n'
      .. "function T:test_it_fails() self:assert_equal(1, 2) end\nreturn T\n")
    failing:close()
    for _, command in ipairs({ "test", "test --jobs=2" }) do
      out, ok = run(command, project)
      self:assert_false(ok, command .. "\n" .. out)
      self:assert_true(out:find("test_it_fails", 1, true) ~= nil, command .. "\n" .. out)
    end
    os.remove(project .. "/tests/failing_test.lua")
  end)
end

function T:test_a_new_project_exports_lints_and_generates()
  with_project(self, function(run, project, base)
    local out, ok = run("contract export --output=openapi.json", project)
    self:assert_true(ok, out)
    out, ok = run("contract lint openapi.json", project)
    self:assert_true(ok, out)
    self:assert_true(out:find("0 error(s)", 1, true) ~= nil, out)

    out, ok = run("generate systemd --user=app --workers=2 --executable=/usr/local/bin/hecate", project)
    self:assert_true(ok, out)
    self:assert_true(out:find("ExecStart=", 1, true) ~= nil and out:find("serve --workers 2", 1, true) ~= nil, out)

    out, ok = run("generate systemd --output=shop.service --executable=/usr/local/bin/hecate", project)
    self:assert_true(ok, out)
    out, ok = run("generate workflow ci", project)
    self:assert_true(ok, out)
    local workflow = assert(io.open(project .. "/.github/workflows/ci.yml", "rb"))
    local workflow_text = workflow:read("a")
    workflow:close()
    self:assert_true(workflow_text:find("hecate install --frozen", 1, true) ~= nil and workflow_text:find("hecate contract lint", 1, true) ~= nil, workflow_text)
    out, ok = run("generate workflow ci", project)
    self:assert_false(ok, out) -- the file exists
    self:assert_true(out:find("--force", 1, true) ~= nil, out)
    out, ok = run("generate workflow ci --force --doc", project)
    self:assert_true(ok, out)
    out, ok = run("new with-ci --ci github")
    self:assert_true(ok, out)
    local created = assert(io.open(base .. "/with-ci/.github/workflows/ci.yml", "rb"))
    self:assert_true(created:read("a"):find("hecate test", 1, true) ~= nil)
    created:close()
    out, ok = run("generate meta", project)
    self:assert_true(ok, out)
    local meta = assert(io.open(project .. "/meta/shop.schemas.lua", "rb"))
    self:assert_true(meta:read("a"):find("---@meta shop.schemas", 1, true) ~= nil)
    meta:close()
  end)
end

function T:test_a_new_project_serves_and_answers_the_health_check()
  with_project(self, function(_, project, _, exe)
    -- `hecate serve` on a free port answers the health check, and stops when it is stopped.
    local reactor_ok, reactor = pcall(require, "hecate.reactor")
    local http_ok, http = pcall(require, "hecate.http")
    local port = free_port()
    if reactor_ok and http_ok and port then
      local status
      progress("starting on port " .. port)
      local ok_serve, err_serve = pcall(reactor.run, function()
        local server = reactor.spawn(exe, { "serve" }, { cwd = project, env = { PORT = tostring(port) }, stdout = "ignore", stderr = "ignore", own_group = true }) -- glossary-ok: an operating-system process
        progress("spawned pid " .. tostring(server.pid))
        local fine_loop, loop_error = pcall(reactor.deadline, 30, function()
          local client = http.Client()
          while true do
            local fine, response = pcall(function() return client:get("http://127.0.0.1:" .. port .. "/health") end)
            if fine then status = response.status return end
            reactor.sleep(0.2)
          end
        end)
        progress("polling ended (" .. tostring(fine_loop) .. ", status " .. tostring(status) .. "), stopping")
        stop_tree(server)
        progress("stopped")
        if not fine_loop then error(loop_error, 0) end
      end)
      self:assert_true(ok_serve, tostring(err_serve))
      self:assert_equal(200, status)
    end
  end)
end

function T:test_the_hello_example_is_a_project_that_hecate_tests_and_lints()
  local exe = built()
  if not exe then return end
  exe = absolute(exe)
  -- A copy: the commands write `lua_modules` and an OpenAPI file, and must not touch the example of the repository
  -- (other tests run it at the same time).
  local base = absolute(assert(util.make_temp_dir(".hecate", "e2e-hello")))
  with_cleanup(base, function()
    local example = base .. "/hello"
    self:assert_true(copy_tree(absolute("examples/hello"), example), "cannot copy examples/hello")
    local linked, linked_ok = util.capture(("%s tools/run.lua link-modules %s 2>&1"):format(util.quote(util.interpreter()), util.quote(example)))
    self:assert_true(linked_ok, linked)
    local out, ok = util.capture(in_directory(example, exe, "test"))
    self:assert_true(ok, out)
    self:assert_true(out:find("6 passed", 1, true) ~= nil, out)
    out, ok = util.capture(in_directory(example, exe, "contract export --output=.hecate-openapi.json"))
    self:assert_true(ok, out)
    out, ok = util.capture(in_directory(example, exe, "contract lint .hecate-openapi.json"))
    self:assert_true(ok, out)
    self:assert_true(out:find("0 error(s)", 1, true) ~= nil, out)
  end)
end

function T:test_every_command_of_the_executable_is_on_the_reference_page_of_the_website()
  local exe = built()
  if not exe then return end
  exe = absolute(exe)
  local help = util.capture(util.quote(exe) .. " --help 2>&1")
  local page = assert(io.open("website/user/en/reference/cli.md", "rb"))
  local text = page:read("a")
  page:close()
  local seen = 0
  for line in help:gmatch("[^\r\n]+") do
    local name = line:match("^  (%l[%l ]-)%s%s+%u")
    if name then
      seen = seen + 1
      self:assert_true(text:find("`hecate " .. name, 1, true) ~= nil, "website/user/en/reference/cli.md does not list `hecate " .. name .. "`")
    end
  end
  self:assert_true(seen >= 18, "the commands of --help were not read: " .. seen)
end

return T
