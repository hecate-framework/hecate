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

function T:test_a_new_project_tests_exports_lints_and_serves()
  local exe = built()
  if not exe then return end
  exe = absolute(exe)
  local base = util.make_temp_dir(".hecate", "e2e")
  assert(base)
  base = absolute(base)
  local function run(command, directory) return util.capture(in_directory(directory or base, exe, command)) end

  local out, ok = run("new shop")
  self:assert_true(ok, out)
  local project = base .. "/shop"
  local linked, linked_ok = util.capture(("%s tools/run.lua link-modules %s 2>&1"):format(util.quote(util.interpreter()), util.quote(project)))
  self:assert_true(linked_ok, linked)

  out, ok = run("test", project)
  self:assert_true(ok, out)
  self:assert_true(out:find("4 passed", 1, true) ~= nil, out)

  out, ok = run("test --jobs=2", project)
  self:assert_true(ok, out)
  self:assert_true(out:find("4 passed", 1, true) ~= nil, out)

  out, ok = run("contract export --output=openapi.json", project)
  self:assert_true(ok, out)
  out, ok = run("contract lint openapi.json", project)
  self:assert_true(ok, out)
  self:assert_true(out:find("0 error(s)", 1, true) ~= nil, out)

  out, ok = run("generate systemd --user=app --workers=2", project)
  self:assert_true(ok, out)
  self:assert_true(out:find("ExecStart=", 1, true) ~= nil and out:find("serve --workers 2", 1, true) ~= nil, out)

  out, ok = run("generate systemd --output=shop.service", project)
  self:assert_true(ok, out)
  out, ok = run("generate meta", project)
  self:assert_true(ok, out)
  local meta = assert(io.open(project .. "/meta/shop.schemas.lua", "rb"))
  self:assert_true(meta:read("a"):find("---@meta shop.schemas", 1, true) ~= nil)
  meta:close()

  -- `hecate serve` on a free port answers the health check, and stops when it is killed.
  local reactor_ok, reactor = pcall(require, "hecate.reactor")
  local http_ok, http = pcall(require, "hecate.http")
  if reactor_ok and http_ok then
    local status
    reactor.run(function()
      local server = reactor.spawn(exe, { "serve" }, { cwd = project, env = { PORT = "18947" }, stdout = "ignore", stderr = "ignore", own_group = true }) -- glossary-ok: an operating-system process
      local client = http.Client()
      for _ = 1, 100 do
        local fine, response = pcall(function() return client:get("http://127.0.0.1:18947/health") end)
        if fine then status = response.status break end
        reactor.sleep(0.2)
      end
      server:kill()
      server:wait()
    end)
    self:assert_equal(200, status)
  end
  util.remove_tree(base)
end

function T:test_the_hello_example_is_a_project_that_hecate_tests_and_lints()
  local exe = built()
  if not exe then return end
  exe = absolute(exe)
  local example = absolute("examples/hello")
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
  os.remove(example .. "/.hecate-openapi.json")
  util.remove_tree(example .. "/lua_modules")
end

return T
