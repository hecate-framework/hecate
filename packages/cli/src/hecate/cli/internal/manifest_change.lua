-- The sequence of the commands that change the manifest (`add`, `remove`): read it, plan the new text, install what the
-- new manifest says, check that the lockfile matches the final text, and only then write the manifest and the lockfile.
-- A failure before the end writes nothing, so a failed install leaves the manifest as it was.
global <const> require, error, pairs, table

local core = require("hecate.core")
local installer = require("hecate.cli.installer")
local lockfile = require("hecate.cli.lockfile")
local manifest_module = require("hecate.cli.manifest")

local MANIFEST = "hecate.project.lua"
local LOCK = "hecate.lock"

---@class hecate.cli.ManifestPlan
---@field install_text string  the manifest to install (the final text, or one with a placeholder constraint)
---@field finish fun(outcome: hecate.cli.InstallResult): string, table  the final manifest text and the report to print

--- Runs a change. `plan` receives the text of the manifest and returns a plan. Suspends (call it inside the reactor).
---@async
---@param context hecate.cli.Context
---@param environment hecate.cli.ProjectEnvironment
---@param plan fun(text: string): hecate.cli.ManifestPlan
---@return table report  what `plan.finish` returned, plus `locked` (the number of rocks)
local function change(context, environment, plan)
  local runtime = context.runtime
  local text = environment.fs.read(MANIFEST)
  if text == nil then
    error(core.ConfigurationError({ message = MANIFEST .. " not found in the current directory: run `hecate new <name>` to create a project" }), 0)
  end
  local planned = plan(text)
  local outcome = installer.install({
    manifest_text = planned.install_text,
    frozen = false,
    fs = environment.fs,
    luarocks = environment.luarocks,
    work_dir = environment.work_dir,
    tree = environment.tree,
    sha256 = environment.sha256,
    lua = runtime.lua_version,
    luarocks_version = runtime.luarocks_version --[[@as string]],
  })
  local final_text, report = planned.finish(outcome)
  -- The lockfile was made from `install_text`; it must also be the lockfile of the final text.
  local problems = lockfile.outdated(outcome.lock, manifest_module.parse(final_text))
  if #problems > 0 then
    error(core.ConfigurationError({
      message = "the lockfile does not match the edited manifest, nothing was written:\n  " .. table.concat(problems, "\n  "),
      context = { problems = problems },
    }), 0)
  end
  environment.fs.write(MANIFEST, final_text)
  environment.fs.write(LOCK, outcome.lock_text)
  local locked = 0
  for _ in pairs(outcome.lock.rocks) do locked = locked + 1 end
  report.locked = locked
  return report
end

return { change = change, MANIFEST = MANIFEST, LOCK = LOCK }
