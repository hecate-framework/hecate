-- `config.load`: reads the layers, merges them, validates the result and freezes it (configuration.md).
-- The Twelve-Factor App, factor III ("Config"): the values that vary between deploys come from the environment.
global <const> require, type, pairs, ipairs, table, string, tostring, error, pcall, load, io, os, package, next, getmetatable, math

local core = require("hecate.core")
local declaration = require("hecate.config.declaration")
local values = require("hecate.config.values")
local Secret = require("hecate.config.secret")
local Configuration = require("hecate.config.configuration")

local MERGE_DEPTH = 1000

local OPTIONS = {
  properties = "table", environment = "string", directory = "string", env_prefix = "string", secrets = "table",
  secrets_directory = "string", secret = "function", getenv = "function", read_file = "function",
}

---@class hecate.config.LoadOptions
---@field properties table<string, hecate.schema.Schema>  the keys of the application (`logging` and `limits` are declared by `config`)
---@field environment? string  name of the environment (default: the variable `<PREFIX>_ENV`, else `development`)
---@field directory? string  directory of the files (default `config`)
---@field env_prefix? string  prefix of the environment variables (default `HECATE`)
---@field secrets? string[]  dotted paths of the leaves whose values are secrets
---@field secrets_directory? string  directory of secret files named like the environment variables
---@field secret? fun(value: any): any  wraps a secret value (default: `hecate.log.Secret` when loaded, else `hecate.config.Secret`)
---@field getenv? fun(name: string): string?  reads a variable (default `os.getenv`)
---@field read_file? fun(path: string): string?, string?, boolean?  content, or nil, a message and whether the file is missing

local function refuse(message, context)
  error(core.ArgumentError("config.load: " .. message, { context = context }), 3)
end

local function check_options(options)
  if type(options) ~= "table" then refuse("options must be a table, got " .. type(options)) end
  for name, value in pairs(options) do
    local expected = OPTIONS[name]
    if expected == nil then
      local known = {}
      for option in pairs(OPTIONS) do known[#known + 1] = option end
      table.sort(known)
      refuse(("unknown option %s (known: %s)"):format(tostring(name), table.concat(known, ", ")))
    end
    if type(value) ~= expected then refuse(("option %s must be a %s, got %s"):format(name, expected, type(value))) end
  end
  if options.properties == nil then refuse("option properties is required") end
  declaration.check_properties(options.properties)
  if options.env_prefix ~= nil and not options.env_prefix:find("^%u[%u%d_]*$") then
    refuse("option env_prefix must be upper case letters, digits and underscores, starting with a letter, got " .. options.env_prefix)
  end
  if options.environment ~= nil and not options.environment:find("^[a-z][a-z0-9_]*$") then
    refuse("option environment must match [a-z][a-z0-9_]*, got " .. options.environment)
  end
  for _, path in ipairs(options.secrets or {}) do
    if type(path) ~= "string" then refuse("option secrets must be a list of dotted paths") end
  end
end

local function configuration_error(message, context)
  return core.ConfigurationError("config.load: " .. message, { context = context })
end

local function default_read_file(path)
  local file, message, errno = io.open(path, "rb")
  if file == nil then return nil, message, errno == 2 end
  local text = file:read("a")
  file:close()
  return text
end

local function escape(segment)
  return (tostring(segment):gsub("~", "~0"):gsub("/", "~1"))
end

local function pointer_of(segments)
  if #segments == 0 then return "" end
  local parts = {}
  for i, segment in ipairs(segments) do parts[i] = escape(segment) end
  return "/" .. table.concat(parts, "/")
end

--- Deep copy of a plain value; a cycle or a nesting beyond `MERGE_DEPTH` is a `ConfigurationError` about `where`.
local function copy(value, depth, where)
  if type(value) ~= "table" then return value end
  if depth > MERGE_DEPTH then
    error(configuration_error(where .. " is nested deeper than " .. MERGE_DEPTH .. " levels (or contains a cycle)", { file = where }), 0)
  end
  local result = {}
  for key, item in pairs(value) do result[key] = copy(item, depth + 1, where) end
  return result
end

local function is_list(value)
  return value[1] ~= nil
end

--- Merges `layer` into `target` (configuration.md, "Merging"), recording the origin of every key in `sources`.
local function merge(target, layer, segments, source, sources, depth, where)
  if depth > MERGE_DEPTH then
    error(configuration_error(where .. " is nested deeper than " .. MERGE_DEPTH .. " levels (or contains a cycle)", { file = where }), 0)
  end
  for key, item in pairs(layer) do
    segments[#segments + 1] = key
    local existing = target[key]
    if type(item) == "table" and type(existing) == "table" and not is_list(item) and not is_list(existing) then
      sources[pointer_of(segments)] = source
      merge(existing, item, segments, source, sources, depth + 1, where)
    else
      target[key] = copy(item, depth + 1, where)
      sources[pointer_of(segments)] = source
      if type(item) == "table" and not is_list(item) then
        -- a fresh object: record the origin of its members too
        local function record(node, path, level)
          if level > MERGE_DEPTH then return end
          for name, member in pairs(node) do
            path[#path + 1] = name
            sources[pointer_of(path)] = source
            if type(member) == "table" then record(member, path, level + 1) end
            path[#path] = nil
          end
        end
        record(item, segments, depth + 1)
      end
    end
    segments[#segments] = nil
  end
end

--- Sets one value in a nested table at `segments`, creating the intermediate objects.
local function set_path(target, segments, value)
  local current = target
  for i = 1, #segments - 1 do
    local nested = current[segments[i]]
    if type(nested) ~= "table" then
      nested = {}
      current[segments[i]] = nested
    end
    current = nested
  end
  current[segments[#segments]] = value
end

--- Evaluates a file of the configuration in an empty environment and returns the table it returns.
local function evaluate(path, text)
  local chunk, message = load(text, "@" .. path, "t", {})
  if chunk == nil then
    error(configuration_error(("%s: %s"):format(path, tostring(message)), { file = path }), 0)
  end
  local ok, result = pcall(chunk)
  if not ok then
    error(configuration_error(("%s: raised an error: %s"):format(path, tostring(result)), { file = path }), 0)
  end
  if type(result) ~= "table" or getmetatable(result) ~= nil then
    error(configuration_error(("%s: must return a table, got %s"):format(path, type(result)), { file = path }), 0)
  end
  return result
end

---@param options hecate.config.LoadOptions
---@return fun(value: any): any
local function wrapper_of(options)
  if options.secret ~= nil then return options.secret end
  local log = package.loaded["hecate.log"]
  if type(log) == "table" and log.Secret ~= nil then return log.Secret --[[@as fun(value: any): any]] end
  return Secret --[[@as fun(value: any): any]]
end

local function strip_line_end(text)
  if text:sub(-2) == "\r\n" then return text:sub(1, -3) end
  if text:sub(-1) == "\n" then return text:sub(1, -2) end
  return text
end

local function by_path(a, b)
  if a.path ~= b.path then return a.path < b.path end
  return a.code < b.code
end

--- The source of a violation: the layer of the longest known ancestor of its path; `-` for a missing required key.
local function origin(sources, violation)
  if violation.code == "required" then return "-" end
  local path = violation.path
  while true do
    if sources[path] ~= nil then return sources[path] end
    if path == "" then return "-" end
    path = path:match("^(.*)/[^/]*$") or ""
  end
end

local function report(environment, problems)
  local lines = { ("config.load: invalid configuration (%d problem%s, environment %s)"):format(
    #problems, #problems == 1 and "" or "s", environment) }
  for _, problem in ipairs(problems) do
    lines[#lines + 1] = ("  %s: %s [%s] (%s)"):format(problem.path == "" and "(root)" or problem.path, problem.message,
      problem.code, problem.source)
  end
  return core.ConfigurationError(table.concat(lines, "\n"), { context = { violations = problems, environment = environment } })
end

--- Loads, merges and validates the configuration of the process (configuration.md). It reads files with `io` and
--- blocks: call it at boot, before the reactor runs; it never suspends.
---
--- Raises `hecate.core.ConfigurationError` for an invalid configuration (every problem found is in
--- `context.violations`, each `{ path, code, message, source }`), and `hecate.core.ArgumentError` for wrong options.
---@param options hecate.config.LoadOptions
---@return hecate.config.Configuration
return function(options)
  check_options(options)
  local getenv = options.getenv or os.getenv
  local read_file = options.read_file or default_read_file
  local prefix = options.env_prefix or "HECATE"
  local directory = options.directory or "config"

  local root = declaration.root(options.properties)
  local index = declaration.index(root)

  -- Leaves and their variable names.
  local leaves, names = {}, {}
  declaration.each_leaf(index, function(node)
    local name = declaration.variable_name(prefix, node.segments)
    if names[name] ~= nil then
      error(configuration_error(("keys %s and %s derive the same environment variable %s"):format(
        names[name], table.concat(node.segments, "."), name), { variable = name }), 0)
    end
    names[name] = table.concat(node.segments, ".")
    leaves[#leaves + 1] = { node = node, name = name, path = table.concat(node.segments, ".") }
  end)

  -- Secrets: declared leaves only.
  local secret_paths, secret_leaf = {}, {}
  for _, leaf in ipairs(leaves) do secret_leaf[leaf.path] = leaf end
  for _, path in ipairs(options.secrets or {}) do
    if secret_leaf[path] == nil then
      refuse(("option secrets: %s is not a declared leaf key"):format(path), { path = path })
    end
    secret_paths[path] = true
  end

  -- The environment.
  local explicit = options.environment ~= nil
  local environment = options.environment
  if environment == nil then
    local named = getenv(prefix .. "_ENV")
    if named ~= nil then
      explicit = true
      if not named:find("^[a-z][a-z0-9_]*$") then
        error(configuration_error(("%s_ENV must match [a-z][a-z0-9_]*, got %q"):format(prefix, named), { variable = prefix .. "_ENV" }), 0)
      end
      environment = named
    else
      environment = "development"
    end
  end

  -- Layers 2 and 3: files.
  local merged, sources, problems = {}, {}, {}
  local function layer_file(name, required)
    local path = directory .. "/" .. name
    local text, message, missing = read_file(path)
    if text == nil then
      if missing and not required then return end
      error(configuration_error(("cannot read %s: %s"):format(path, tostring(message)), { file = path }), 0)
    end
    merge(merged, evaluate(path, text), {}, path, sources, 1, path)
  end
  layer_file("default.lua", false)
  layer_file(environment .. ".lua", explicit)

  -- A coerced text: stores it or records the violations.
  local function coerced(leaf, text, source, target)
    local ok, result = leaf.node.schema:coerce(text)
    if ok then
      set_path(target, leaf.node.segments, result)
      return
    end
    for _, violation in ipairs(result) do
      problems[#problems + 1] = {
        path = pointer_of(leaf.node.segments) .. violation.path, code = violation.code,
        message = violation.message, source = source,
      }
    end
  end

  -- Layer 4: environment variables.
  local from_env, env_source = {}, {}
  for _, leaf in ipairs(leaves) do
    local text = getenv(leaf.name)
    if text ~= nil then
      local source = "environment variable " .. leaf.name
      env_source[leaf.path] = source
      coerced(leaf, text, source, from_env)
    end
  end
  local function apply(layer, source_of)
    for _, leaf in ipairs(leaves) do
      local node = layer
      for _, segment in ipairs(leaf.node.segments) do
        node = type(node) == "table" and node[segment] or nil
      end
      if node ~= nil then
        set_path(merged, leaf.node.segments, copy(node, 1, leaf.path))
        sources[pointer_of(leaf.node.segments)] = source_of[leaf.path]
      end
    end
  end
  apply(from_env, env_source)

  -- Layer 5: secret files.
  local from_files, file_source = {}, {}
  for _, leaf in ipairs(leaves) do
    if secret_paths[leaf.path] then
      local path = getenv(leaf.name .. "_FILE")
      local named = path ~= nil
      if not named and options.secrets_directory then path = options.secrets_directory .. "/" .. leaf.name end
      if path ~= nil then
        local text, message, missing = read_file(path)
        if text ~= nil then
          local source = "secret file " .. path
          file_source[leaf.path] = source
          coerced(leaf, strip_line_end(text), source, from_files)
        elseif named or not missing then
          error(configuration_error(("cannot read secret file %s: %s"):format(path, tostring(message)), { file = path }), 0)
        end
      end
    end
  end
  apply(from_files, file_source)

  -- Validation, with the defaults of the schema.
  local ok, built = root:build(merged)
  if not ok then
    for _, violation in ipairs(built) do
      problems[#problems + 1] = {
        path = violation.path, code = violation.code, message = violation.message, source = origin(sources, violation),
      }
    end
  else
    -- The rule that a schema cannot express (configuration.md, "Validation").
    local logging = built.logging
    local has_file = false
    for _, sink in ipairs(logging.sinks) do has_file = has_file or sink == "file" end
    if has_file and (logging.file == nil or logging.file.path == nil) then
      problems[#problems + 1] = {
        path = "/logging/file/path", code = "required", source = "-",
        message = "the property is required when logging.sinks contains file",
      }
    end
  end
  if #problems > 0 then
    table.sort(problems, by_path)
    error(report(environment, problems), 0)
  end

  local frozen = values.freeze(built, wrapper_of(options), secret_paths, "")
  return Configuration(frozen, index, sources, environment)
end
