-- `hecate doctor`: diagnoses the environment (versions, LuaRocks, libuv, the native codec, SHA-256, a C compiler) and the
-- project of the current directory.
global <const> require, pcall, io, os, package, string, table, ipairs, tostring

local doctor = require("hecate.cli.doctor")
local manifest_module = require("hecate.cli.manifest")
local project_process = require("hecate.cli.internal.project_process")

--- The program the project interpreter runs to read `hecate.core.version`.
local VERSION_PROGRAM = 'io.write(require("hecate.core").version or "")'

local MARK = { ok = "ok  ", warn = "warn", fail = "FAIL" }

--- The `doctor` command.
---@class hecate.cli.commands.doctor: hecate.cli.Command
---@field execute fun(context: hecate.cli.Context, probes: hecate.cli.DoctorProbes): integer
local command = {
  name = "doctor",
  summary = "Diagnose the environment and the project: versions, LuaRocks, native modules, compiler",
}

--- Runs the checks with the given probes.
---@param context hecate.cli.Context
---@param probes hecate.cli.DoctorProbes
---@return integer exit_code
function command.execute(context, probes)
  local manifest_text = probes.read("hecate.project.lua")
  local project
  if manifest_text ~= nil then
    local ok, err = pcall(manifest_module.parse, manifest_text)
    project = {
      manifest_error = (not ok) and (err --[[@as hecate.core.Error]]).message or nil,
      has_lock = probes.read("hecate.lock") ~= nil,
    }
  end
  local checks = doctor.run(context.runtime, probes, project)
  local code, failures, warnings = doctor.summary(checks)

  local lines = {}
  for _, entry in ipairs(checks) do
    lines[#lines + 1] = string.format("[%s] %-20s %s", MARK[entry.status], entry.name, entry.detail)
    if entry.fix then lines[#lines + 1] = "       -> " .. entry.fix end
  end
  lines[#lines + 1] = string.format("%d problem(s), %d warning(s). %s", failures, warnings, failures > 0 and "Fix the problems above." or "The environment is fit.")
  context.emit({ ok = code == 0, platform = context.runtime.platform, checks = checks }, table.concat(lines, "\n"))
  return code
end

--- The real probes: `require`, the PATH, the file system and the digest module of the CLI.
---@param context hecate.cli.Context
---@return hecate.cli.DoctorProbes
local function real_probes(context)
  local windows = package.config:sub(1, 1) == "\\"
  return {
    json_works = function()
      -- The native module loads on first use: encode something.
      local ok, err = pcall(function() return require("hecate.json").encode({ ok = true }) end)
      return ok, ok and nil or tostring((err --[[@as hecate.core.Error]]).message or err)
    end,
    on_path = function(program)
      local probe = windows and ("where " .. program .. " >NUL 2>&1") or ("command -v " .. program .. " >/dev/null 2>&1")
      return os.execute(probe) == true
    end,
    read = function(path)
      local file = io.open(path, "rb")
      if not file then return nil end
      local text = file:read("a")
      file:close()
      return text
    end,
    project_core_version = function()
      local reactor = require("hecate.reactor")
      local process = {
        run_process = function(program, args, options) return reactor.run_process(program, args, options) end,
        interpreter = context.runtime.lua_interpreter or "lua",
        interpreter_arguments = context.runtime.lua_interpreter_arguments,
      }
      local ok, result = pcall(function()
        return reactor.run(function() return project_process.run(context, process, VERSION_PROGRAM, nil, "reading hecate.core.version") end)
      end)
      if ok then return (result.stdout:gsub("%s+$", "")) end
      local message = tostring((result --[[@as hecate.core.Error]]).message or result)
      if message:find("module 'hecate.core' not found", 1, true) then return nil end
      return nil, message
    end,
    digest_backend = function()
      local ok, digest = pcall(require, "hecate.cli.digest")
      return ok and digest.backend_name or nil
    end,
  }
end

--- Runs `hecate doctor` with the real probes.
---@param context hecate.cli.Context
---@return integer exit_code
function command.run(context)
  return command.execute(context, real_probes(context))
end

return command
