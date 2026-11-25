local test = require("harness.test")
local app = require("hecate.cli.app")
local systemd = require("hecate.cli.commands.generate_systemd")
local T = test.Case("CliGenerateSystemdTest")
local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
local nested = dofile(here .. "/../support/nested_guard.lua")

local MANIFEST = 'return { name = "shop", version = "0.1.0" }'

local function run(args, opts)
  opts = opts or {}
  local project_dir = opts.project_dir or "/srv/shop"
  local written = {}
  local files = opts.manifest == false and {} or { ["hecate.project.lua"] = MANIFEST }
  local dependencies = {
    fs = { read = nested.outside(function(path) return files[path] end) }, -- the real read starts a reactor: valid only outside `run`
    write = function(path, text) written[path] = text end,
    exists = function(path) return path == opts.existing end,
    run = nested.run,
  }
  local arguments
  if not opts.plain then arguments = { "--lua" } end
  local command = setmetatable({ run = function(context) return systemd.execute(context, dependencies) end }, { __index = systemd })
  local out, err = {}, {}
  local code = app.run(args, {
    commands = { command },
    runtime = { hecate_version = "0.1.0", lua_version = "5.5.1", platform = "linux-x86_64", project_dir = project_dir,
      lua_interpreter = "/usr/local/bin/hecate", lua_interpreter_arguments = arguments },
    write = function(text) out[#out + 1] = text end,
    write_error = function(text) err[#err + 1] = text end,
  })
  return code, table.concat(out, "\n"), table.concat(err, "\n"), written
end

function T:test_the_unit_runs_serve_in_the_project_and_reloads_on_sighup()
  local code, out = run({ "generate", "systemd" })
  self:assert_equal(0, code)
  for _, line in ipairs({ "WorkingDirectory=/srv/shop", "ExecStart=/usr/local/bin/hecate serve", "ExecReload=/bin/kill -HUP $MAINPID",
    "KillSignal=SIGTERM", "Restart=on-failure", "WantedBy=multi-user.target", "Description=shop (Hecate application)" }) do
    self:assert_true(out:find(line, 1, true) ~= nil, line .. "\n" .. out)
  end
  self:assert_true(out:find("User=", 1, true) == nil)
end

function T:test_user_workers_and_executable_are_written()
  local _, out = run({ "generate", "systemd", "--user=hecate", "--workers=4", "--executable=/opt/hecate/bin/hecate" })
  self:assert_true(out:find("User=hecate", 1, true) ~= nil, out)
  self:assert_true(out:find("ExecStart=/opt/hecate/bin/hecate serve --workers 4", 1, true) ~= nil, out)
end

function T:test_output_writes_a_file_and_keeps_an_existing_one()
  local code, _, _, written = run({ "generate", "systemd", "--output=shop.service" })
  self:assert_equal(0, code)
  self:assert_true(written["shop.service"]:find("[Service]", 1, true) ~= nil)
  local code2, _, err, written2 = run({ "generate", "systemd", "--output=shop.service" }, { existing = "shop.service" })
  self:assert_equal(1, code2)
  self:assert_true(err:find("--force", 1, true) ~= nil, err)
  self:assert_equal(nil, next(written2))
  local code3, _, _, written3 = run({ "generate", "systemd", "--output=shop.service", "--force" }, { existing = "shop.service" })
  self:assert_equal(0, code3)
  self:assert_true(written3["shop.service"] ~= nil)
end

function T:test_a_plain_lua_needs_an_executable_and_workers_are_checked()
  local code, _, err = run({ "generate", "systemd" }, { plain = true })
  self:assert_equal(2, code)
  self:assert_true(err:find("--executable", 1, true) ~= nil, err)
  local code2, _, err2 = run({ "generate", "systemd", "--workers=zero" })
  self:assert_equal(2, code2)
  self:assert_true(err2:find("--workers", 1, true) ~= nil, err2)
end

function T:test_a_user_with_a_line_break_cannot_add_directives_to_the_unit()
  for _, user in ipairs({ "x\nExecStartPre=/bin/sh -c evil", "x\rExecStartPre=y", "root;id", "a b", "", "-x" }) do
    local code, out, err = run({ "generate", "systemd", "--user=" .. user })
    self:assert_equal(2, code, user)
    self:assert_equal("", out)
    self:assert_true(err:find("--user", 1, true) ~= nil, err)
    self:assert_true(err:find("\nExecStartPre", 1, true) == nil, err) -- the value is not echoed with its line break
  end
  local _, out = run({ "generate", "systemd", "--user=svc_web-1.a" })
  self:assert_true(out:find("User=svc_web-1.a", 1, true) ~= nil, out)
end

function T:test_a_control_character_in_the_executable_or_the_directory_is_refused()
  local code, _, err = run({ "generate", "systemd", "--executable=/opt/h\nExecStartPre=/bin/evil" })
  self:assert_equal(2, code)
  self:assert_true(err:find("control character", 1, true) ~= nil, err)
  local code2, _, err2 = run({ "generate", "systemd" }, { project_dir = "/srv/a\nUser=root" })
  self:assert_equal(2, code2)
  self:assert_true(err2:find("working directory", 1, true) ~= nil, err2)
end

function T:test_spaces_and_percent_are_escaped_for_systemd()
  local _, out = run({ "generate", "systemd", "--executable=/opt/my apps/100%/hecate" }, { project_dir = "/srv/my shop/50%" })
  self:assert_true(out:find('ExecStart="/opt/my apps/100%%/hecate" serve', 1, true) ~= nil, out)
  self:assert_true(out:find("WorkingDirectory=/srv/my shop/50%%\n", 1, true) ~= nil, out)
  local _, quoted = run({ "generate", "systemd", '--executable=/opt/a"b$c/hecate' })
  self:assert_true(quoted:find('ExecStart="/opt/a\\"b$$c/hecate" serve', 1, true) ~= nil, quoted)
end

function T:test_the_directory_and_the_environment_file_are_those_of_the_server()
  local code, out = run({ "generate", "systemd", "--working-directory=/srv/prod/shop", "--environment-file=/etc/shop/env" })
  self:assert_equal(0, code)
  self:assert_true(out:find("WorkingDirectory=/srv/prod/shop\n", 1, true) ~= nil, out)
  self:assert_true(out:find("EnvironmentFile=/etc/shop/env\n", 1, true) ~= nil, out)
  self:assert_true(out:find("/srv/shop", 1, true) == nil, out) -- the directory of the machine that generated it is not in the unit
  local _, plain = run({ "generate", "systemd" })
  self:assert_true(plain:find("EnvironmentFile", 1, true) == nil)
  for _, args in ipairs({ { "--working-directory=relative" }, { "--environment-file=env" }, { "--environment-file=/etc/a\nB=c" }, { "--working-directory=/a\nB=c" } }) do
    local bad, _, err = run({ "generate", "systemd", args[1] })
    self:assert_equal(2, bad, args[1])
    self:assert_true(err:find("hecate generate systemd", 1, true) ~= nil, err)
  end
end

function T:test_a_project_is_required()
  local code, _, err = run({ "generate", "systemd" }, { manifest = false })
  self:assert_true(code ~= 0, tostring(code))
  self:assert_true(err:find("hecate.project.lua", 1, true) ~= nil, err)
end

return T
