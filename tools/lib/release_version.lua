-- The version of a release of Hecate: the single validator of the tools (the shell form of the same grammar is in
-- `packages/actions/setup/action.yml`, and `tools/tests/release_version_test.lua` checks that the two agree).
--
-- Grammar (LuaRocks version form, no `v` prefix; owner decision of 2026-11-25):
--
--   release  = base "-" revision
--   base     = X "." Y "." Z [ pre ]            (what the `VERSION` file holds, and what `hecate version` prints)
--   pre      = ( "alpha" | "beta" | "rc" | "pre" ) number
--
-- The four tokens are the ones `luarocks.core.vers` orders before the final release (alpha < beta < pre < rc < final);
-- `dev`, `scm` and `cvs` order after it and are refused. The ordering is informational here.
--
-- Equivalent regular expression (POSIX ERE, as used by the setup action):
--   ^[0-9]+\.[0-9]+\.[0-9]+((alpha|beta|rc|pre)[0-9]+)?-[0-9]+$
local M = {}

--- The pre-release tokens, in the order LuaRocks sorts them (`luarocks.core.vers`, `deltas`).
M.PRERELEASE_TOKENS = { "alpha", "beta", "pre", "rc" }

--- The grammar as an ERE, for the shell and the documentation.
M.ERE = "^[0-9]+\\.[0-9]+\\.[0-9]+((alpha|beta|rc|pre)[0-9]+)?-[0-9]+$"

--- Splits a base version `X.Y.Z[pre]`.
---@param base string
---@return string? numeric     `X.Y.Z`
---@return string? prerelease  `rc1`, or "" for a final version
function M.split_base(base)
  if type(base) ~= "string" then return nil end
  local numeric, rest = base:match("^(%d+%.%d+%.%d+)(.*)$")
  if not numeric then return nil end
  if rest == "" then return numeric, "" end
  for _, token in ipairs(M.PRERELEASE_TOKENS) do
    if rest:match("^" .. token .. "%d+$") then return numeric, rest end
  end
  return nil
end

--- Whether `base` is `X.Y.Z` or `X.Y.Z` followed directly by a pre-release (`0.4.2rc1`).
---@param base string
---@return boolean
function M.is_base(base)
  return (M.split_base(base)) ~= nil
end

--- Splits `<base>-<revision>`.
---@param version string
---@return string? base       `X.Y.Z[pre]`
---@return string? revision   digits
function M.parse(version)
  if type(version) ~= "string" then return nil end
  local base, revision = version:match("^([^%-]+)%-(%d+)$")
  if not base or not M.is_base(base) then return nil end
  return base, revision
end

--- Whether the base version carries a pre-release part.
---@param base string
---@return boolean
function M.is_prerelease(base)
  local numeric, pre = M.split_base(base)
  return numeric ~= nil and pre ~= ""
end

return M
