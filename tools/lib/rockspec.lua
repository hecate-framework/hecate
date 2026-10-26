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

return M
