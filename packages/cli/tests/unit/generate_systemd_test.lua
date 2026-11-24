local test = require("harness.test")
local app = require("hecate.cli.app")
local systemd = require("hecate.cli.commands.generate_systemd")
local T = test.Case("CliGenerateSystemdTest")

local MANIFEST = 'return { name = "shop", version = "0.1.0" }'

local function run(args, opts)
  opts = opts or {}
  local written = {}
  local files = opts.manifest == false and {} or { ["hecate.project.lua"] = MANIFEST }
  local dependencies = {
    fs = { read = function(path) return files[path] end },
    write = function(path, text) written[path] = text end,
    exists = function(path) return path == opts.existing end,
    run = function(task) return task() end,
  }
  local arguments
  if not opts.plain then arguments = { "--lua" } end
  local command = setmetatable({ run = function(context) return systemd.execute(context, dependencies) end }, { __index = systemd })
  local out, err = {}, {}
  local code = app.run(args, {
    commands = { command },
    runtime = { hecate_version = "0.1.0", lua_version = "5.5.1", platform = "linux-x86_64", project_dir = "/srv/shop",
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

function T:test_a_project_is_required()
  local code, _, err = run({ "generate", "systemd" }, { manifest = false })
  self:assert_true(code ~= 0, tostring(code))
  self:assert_true(err:find("hecate.project.lua", 1, true) ~= nil, err)
end

return T
