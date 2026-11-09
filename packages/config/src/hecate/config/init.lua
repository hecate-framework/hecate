-- hecate.config: layered configuration validated by schemas at boot (docs/architecture/configuration.md).
global <const> require

local declaration = require("hecate.config.declaration")

--- Layered configuration: schema defaults, `config/default.lua`, `config/<environment>.lua`, environment variables and
--- secret files, merged, validated against a schema and returned as an immutable `Configuration`.
---@class hecate.config
---@field Configuration hecate.config.Configuration  the result of `load`
---@field Section hecate.config.Section  an immutable object or map of a configuration
---@field List hecate.config.List  an immutable array of a configuration
---@field Secret hecate.config.Secret  the fallback secret object (same interface as `hecate.log.Secret`)
---@field SEVERITIES string[]  the eight severity names of RFC 5424, most urgent first (values of `logging.severity`)
---@field MAX_DEPTH_CEILING integer  the highest `limits.max_depth`, the cap of `hecate.json`
---@field load fun(options: hecate.config.LoadOptions): hecate.config.Configuration
---@field variable_name fun(prefix: string, segments: string[]): string
local config = {
  ---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
  Configuration = require("hecate.config.configuration"),
  ---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
  Section = require("hecate.config.values").Section,
  ---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
  List = require("hecate.config.values").List,
  ---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
  Secret = require("hecate.config.secret"),
  SEVERITIES = declaration.SEVERITIES,
  MAX_DEPTH_CEILING = declaration.MAX_DEPTH_CEILING,
  load = require("hecate.config.load"),
}

--- The name of the environment variable that sets the key at `segments` (`HECATE_LIMITS__MAX_DEPTH` for
--- `{ "limits", "max_depth" }`): the prefix, an underscore, the upper-cased segments joined by two underscores.
---@param prefix string  for example `HECATE`
---@param segments string[]  the path of the key
---@return string name
function config.variable_name(prefix, segments)
  return declaration.variable_name(prefix, segments)
end

return config
