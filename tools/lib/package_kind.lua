-- The kind of a package directory: `rock` (the default: a Lua rock with a rockspec, a module root and tests) or
-- `actions` (GitHub Actions, no Lua: `packages/actions`, mirror `hecate-framework/hecate-actions`, ADR 0017).
--
-- The kind is the `Kind` row of the README table of the package (the file every package tool already reads); a README
-- without the row is a rock. A package that is not a rock is exempt, explicitly and only from the checks that need a
-- rockspec: version, layer, dependency graph, rockspec lint and generation, CI matrix. `check-package-structure`
-- still verifies its README, CLAUDE.md, agent and mirror naming (pure functions, except `rocks`).
local util = require("lib.util")

local M = {}

--- The kinds that exist.
M.KINDS = { rock = true, actions = true }

--- The kind written in a README, or `rock` when there is no `Kind` row.
---@param readme string?
---@return string kind
function M.of(readme)
  local kind = (readme or ""):match("\n|%s*Kind%s*|%s*`?([%w%-]+)`?[^|]-%s*|")
  return kind or "rock"
end

--- True when the README declares a kind that does not exist.
---@param readme string?
---@return boolean
function M.known(readme) return M.KINDS[M.of(readme)] == true end

--- The package directories of a repository that are Lua rocks, sorted (the exemption of the other kinds).
---@param root string
---@return string[]
function M.rocks(root)
  local names = {}
  for _, name in ipairs(util.list_dir(root .. "/packages")) do
    local f = io.open(("%s/packages/%s/README.md"):format(root, name), "rb")
    local text = f and f:read("a")
    if f then f:close() end
    if M.of(text) == "rock" then names[#names + 1] = name end
  end
  return names
end

return M
