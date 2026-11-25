-- The checks of `hecate doctor`: is the environment fit to build and run a Hecate project? Pure over what the caller
-- found out (`runtime`) and three probes, so every outcome is testable.
global <const> ipairs, table, tostring

---@alias hecate.cli.CheckStatus "ok"|"warn"|"fail"

---@class hecate.cli.Check
---@field name string  what is checked
---@field status hecate.cli.CheckStatus
---@field detail string  what was found
---@field fix? string  what to do when the status is not `ok`

---@class hecate.cli.DoctorProbes
---@field json_works fun(): boolean, string?  whether `hecate.json` can encode a value (its native module loads on first use, `require` alone proves nothing), and the error when it cannot
---@field on_path fun(program: string): boolean  whether the program is found on the PATH
---@field read fun(path: string): string?  the text of a file, nil when it does not exist
---@field digest_backend fun(): string?  the SHA-256 backend in use (`digest`), nil when it does not load
---@field project_core_version? fun(): string?, string?  `hecate.core.version` as the project resolves it (a child process with the module path of the project): the version (empty when the module has no `version` field), nil when `hecate.core` is not installed in the project, nil and the error when the question could not be asked; absent: the check is skipped

--- Diagnosing the environment.
---@class hecate.cli.doctor
local M = {}

--- The C compilers a native rock can be built with, by platform family.
M.COMPILERS = { "cc", "gcc", "clang", "cl" }

local function check(name, status, detail, fix)
  return { name = name, status = status, detail = detail, fix = fix }
end

--- The version-skew check: the executable embeds its own copy of `hecate.core` and the other packages it needs, and the
--- project resolves its own; a difference is a warning, never a failure.
---@param embedded string  the version the executable was built from (`hecate.cli.main.embedded_version`)
---@param project_version? string  `hecate.core.version` of the project (nil: not installed)
---@param problem? string  why the version could not be read
---@return hecate.cli.Check
function M.version_skew(embedded, project_version, problem)
  local name = "hecate version"
  if project_version == nil then
    if problem then
      return check(name, "warn", "the version of hecate.core in the project could not be read: " .. tostring(problem):match("^[^\n]*"), "run `hecate install`")
    end
    return check(name, "ok", "executable " .. embedded .. "; hecate.core is not installed in the project yet (run `hecate install`)")
  end
  if project_version == embedded then return check(name, "ok", "executable and project are at " .. embedded) end
  local shown = project_version == "" and "no version field" or project_version
  return check(name, "warn", "executable " .. embedded .. ", project hecate.core " .. shown,
    "run `hecate install` to update the project, or update the executable, so that both are at the same version")
end

--- Runs every check. `project` is the manifest and lockfile of the current directory, when `hecate.project.lua` exists.
---@param runtime hecate.cli.Runtime
---@param probes hecate.cli.DoctorProbes
---@param project? { manifest_error?: string, has_lock: boolean }
---@return hecate.cli.Check[] checks
function M.run(runtime, probes, project)
  local checks = {}

  if runtime.lua_version:match("^5%.5") then
    checks[#checks + 1] = check("Lua", "ok", runtime.lua_version)
  else
    checks[#checks + 1] = check("Lua", "fail", runtime.lua_version .. " (Hecate needs Lua 5.5)", "run hecate with a Lua 5.5 interpreter")
  end

  if runtime.luarocks_version then
    checks[#checks + 1] = check("LuaRocks", "ok", runtime.luarocks_version .. (runtime.luarocks_program and " (embedded in the executable)" or ""))
  else
    checks[#checks + 1] = check("LuaRocks", "fail", "not found on the PATH", "install LuaRocks 3.x (https://luarocks.org) and put it on the PATH")
  end

  if runtime.libuv_version then
    checks[#checks + 1] = check("libuv (luv)", "ok", runtime.libuv_version)
  else
    checks[#checks + 1] = check("libuv (luv)", "fail", "the luv module does not load", "luarocks install luv")
  end

  local json_ok, json_error = probes.json_works()
  if json_ok then
    checks[#checks + 1] = check("hecate.json", "ok", "native codec loaded")
  else
    checks[#checks + 1] = check("hecate.json", "warn", "does not load: " .. tostring(json_error):match("^[^\n]*"),
      "build or install the native module (in a checkout: lua tools/run.lua build-native json); `--json` needs it")
  end

  local backend = probes.digest_backend()
  if backend == "digest" then
    checks[#checks + 1] = check("SHA-256", "ok", "digest rock")
  else
    checks[#checks + 1] = check("SHA-256", "fail", "the digest rock does not load", "luarocks install digest")
  end

  local compiler
  for _, program in ipairs(M.COMPILERS) do
    if probes.on_path(program) then compiler = program break end
  end
  if compiler then
    checks[#checks + 1] = check("C compiler", "ok", compiler)
  else
    checks[#checks + 1] = check("C compiler", "warn", "none of " .. table.concat(M.COMPILERS, ", ") .. " on the PATH",
      "install a C compiler to build native rocks (Windows: the Visual Studio Build Tools)")
  end

  if project then
    if project.manifest_error then
      checks[#checks + 1] = check("hecate.project.lua", "fail", project.manifest_error, "fix the manifest")
    else
      checks[#checks + 1] = check("hecate.project.lua", "ok", "valid")
      if project.has_lock then
        checks[#checks + 1] = check("hecate.lock", "ok", "present")
      else
        checks[#checks + 1] = check("hecate.lock", "warn", "missing", "run `hecate install` and commit the lockfile")
      end
      if probes.project_core_version then checks[#checks + 1] = M.version_skew(runtime.hecate_version, probes.project_core_version()) end
    end
  end
  return checks
end

--- The exit code and the summary of a list of checks: 1 when one failed, 0 otherwise.
---@param checks hecate.cli.Check[]
---@return integer exit_code
---@return integer failures
---@return integer warnings
function M.summary(checks)
  local failures, warnings = 0, 0
  for _, entry in ipairs(checks) do
    if entry.status == "fail" then failures = failures + 1 elseif entry.status == "warn" then warnings = warnings + 1 end
  end
  return failures > 0 and 1 or 0, failures, warnings
end

return M
