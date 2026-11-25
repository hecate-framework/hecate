-- Helpers of the `gen-rockspecs` task (pure functions).
local M = {}

--- The `build = { ... }` table of a rockspec text, or nil.
---@param text string
---@return string?
function M.build_block(text)
  return text:match("\nbuild = (%b{})")
end

--- Puts the `build` table of an existing rockspec into a generated one: the generator writes the default build
--- (`builtin`, no modules), and a package that ships native modules declares its own (`build.install.lib`, OQ-41),
--- which a regeneration must not erase.
---@param generated string
---@param existing string?  the rockspec on disk, if any
---@return string
function M.keep_build(generated, existing)
  local kept = existing and M.build_block(existing)
  if not kept then return generated end
  local default = M.build_block(generated)
  if not default or default == kept then return generated end
  local first, last = generated:find("\nbuild = " .. default:gsub("%p", "%%%0"))
  if not first then return generated end
  return generated:sub(1, first - 1) .. "\nbuild = " .. kept .. generated:sub(last + 1)
end

--- Packages released outside the lockstep version of ADR 0005, with the licence they declare. The rock version of
--- `unicode-data` is the Unicode version followed by a revision (`18.0.0-1`, ADR 0032); it is released on the
--- Unicode schedule and never bumped with `VERSION`.
M.exempt = { ["unicode-data"] = { license = "Unicode-3.0", versioned_by = "Unicode" } }

--- Packages whose top-level module has no `version` field of the package: the data rock is released outside the
--- lockstep and its module exposes `unicode_version`, the Unicode version, which is also its rock version (ADR 0032).
--- `hecate.unicode` is not exempt: its `version` is the lockstep `VERSION` and it reports the Unicode version as
--- `unicode_version` (owner decision of 2026-11-25, OQ-150).
M.version_field_exempt = { ["unicode-data"] = true }

--- The `version` field of a top-level module, read from its text: a `version = "..."` entry of the table constructor
--- (indented by two spaces) or a `<name>.version = "..."` assignment at the start of a line.
---@param text string
---@return string?
function M.module_version(text)
  local v = ("\n" .. text):match('\n  version = "([^"\n]*)"') or ("\n" .. text):match('\n[%a_][%w_]*%.version = "([^"\n]*)"')
  return v
end

--- The licence identifier a package rockspec declares (MIT unless the package is listed in `M.exempt`).
---@param name string
---@return string
function M.license(name) return M.exempt[name] and M.exempt[name].license or "MIT" end

--- The dependencies of a package from the "Depends on" cell of its README: `{ name, minimum? }`. A dependency
--- written `[`unicode-data`](../unicode-data) (>= 18.0.0)` carries a minimum version.
---@param cell string
---@return { name: string, minimum: string? }[]
function M.readme_dependencies(cell)
  local out = {}
  for name, rest in cell:gmatch("%[`([%w_%-]+)`%]%b()([^%[]*)") do
    out[#out + 1] = { name = name, minimum = rest:match("%(>=%s*([%d%.]+)%)") }
  end
  return out
end

--- The rockspec dependency string of a hecate package: `"hecate-x"` or `"hecate-x >= 1.2.3"`.
---@param dependency { name: string, minimum: string? }
---@return string
function M.dependency_string(dependency)
  return ('"hecate-%s%s"'):format(dependency.name, dependency.minimum and (" >= " .. dependency.minimum) or "")
end

--- Problems of the constraints on `hecate-*` dependencies of a rockspec text: inside the lockstep a dependency
--- has none; the only constraint allowed is a lower bound `>= x.y.z` (no exact pin, no upper bound; ADR 0032).
---@param rock string
---@param text string
---@return string[]
function M.constraint_problems(rock, text)
  local problems = {}
  local block = text:match("\ndependencies%s*=%s*(%b{})") or ""
  for name, constraint in block:gmatch('"(hecate[%w%-]*)%s*([^"]*)"') do
    if constraint ~= "" and not constraint:match("^>=%s*%d+%.%d+%.%d+$") then
      problems[#problems + 1] = ("%s: dependency %s has constraint '%s': only a lower bound '>= x.y.z' is allowed"):format(rock, name, constraint)
    end
  end
  return problems
end

--- Problem with the version of a released rockspec, or nil: `scm-1` is the development version; a package in the
--- lockstep is at `VERSION-<revision>`, an exempt package at `<unicode version>-<revision>`.
---@param name string  package name
---@param version string  rockspec version
---@param lockstep string  content of VERSION
---@param unicode_version string?  the Unicode version of `unicode-data`
---@return string?
function M.version_problem(name, version, lockstep, unicode_version)
  if version == "scm-1" then return nil end
  local expected = M.exempt[name] and unicode_version or lockstep
  if not expected then return ("%s: no version to compare with"):format(name) end
  if not version:match("^" .. expected:gsub("%p", "%%%0") .. "%-%d+$") then
    return ("%s: version %s is not %s-<revision> (%s)"):format(name, version, expected,
      M.exempt[name] and "the Unicode version, ADR 0032" or "VERSION, ADR 0005")
  end
  return nil
end

return M
