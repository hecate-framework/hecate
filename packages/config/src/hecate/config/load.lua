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
  secrets_directory = "string", wrap_secret = "function", getenv = "function", read_file = "function",
}

---@class hecate.config.LoadOptions
---@field properties table<string, hecate.schema.Schema>  the keys of the application (`logging`, `limits`, `errors`, `requests` and `server` are declared by `config`; a name contains no `.`)
---@field environment? string  name of the environment (default: the variable `<PREFIX>_ENV`, else `production`)
---@field directory? string  directory of the files (default `config`)
---@field env_prefix? string  prefix of the environment variables (default `HECATE`)
---@field secrets? string[]  dotted paths of the leaves whose values are secrets (a list: keys 1 to n)
---@field secrets_directory? string  directory of secret files named like the environment variables
---@field wrap_secret? fun(value: any): any  wraps a secret value (default: `hecate.log.Secret` when loaded, else `hecate.config.Secret`)
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
  if options.env_prefix ~= nil and not options.env_prefix:find(declaration.PREFIX_PATTERN) then
    refuse("option env_prefix must be upper case letters, digits and underscores, starting with a letter, got " .. options.env_prefix)
  end
  if options.environment ~= nil and not options.environment:find("^[a-z][a-z0-9_]*$") then
    refuse("option environment must match [a-z][a-z0-9_]*, got " .. options.environment)
  end
  -- A map or a list with any other key would be read by `ipairs` in part only, leaving keys unprotected.
  if options.secrets ~= nil and not declaration.is_sequence(options.secrets) then
    refuse("option secrets must be a list of dotted paths (keys 1 to n), not a map")
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
  local text, read_message = file:read("a")
  file:close()
  -- A directory opens but cannot be read: `read` returns nil and the message of the system.
  if text == nil then return nil, read_message or "the file cannot be read", false end
  return text
end

--- Joins a directory and a file name, without doubling a separator the directory already ends with.
local function join(directory, name)
  if directory:find("[/\\]$") then return directory .. name end
  return directory .. "/" .. name
end

--- Removes a leading UTF-8 byte order mark (some editors add one; Lua would read it as a syntax error).
local function strip_bom(text)
  if text:sub(1, 3) == "\239\187\191" then return text:sub(4) end
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

local function unescape(segment)
  return (segment:gsub("~1", "/"):gsub("~0", "~"))
end

--- The dotted path of a JSON Pointer (`/database/port` gives `database.port`; the root gives the empty string).
local function dotted_of(pointer)
  local parts = {}
  for segment in pointer:gmatch("/([^/]*)") do parts[#parts + 1] = unescape(segment) end
  return table.concat(parts, ".")
end

--- The shape of the keys of a table of a file: `"array"` (keys exactly 1 to n, n at least 1) or `"object"` (anything
--- else, the empty table included), and the keys that do not fit, each `{ key, message }`, sorted.
local function shape_of(value)
  local strings, integers, others = 0, {}, {}
  for key in pairs(value) do
    if type(key) == "string" then
      strings = strings + 1
    elseif math.type(key) == "integer" and key >= 1 then
      integers[#integers + 1] = key
    else
      others[#others + 1] = key
    end
  end
  table.sort(integers)
  local offending = {}
  for _, key in ipairs(others) do
    offending[#offending + 1] = { key = key, message = ("a key must be a string or an array index, got %s %s"):format(
      math.type(key) or type(key), tostring(key)) }
  end
  if #integers > 0 and strings > 0 then
    -- named keys and items: neither an object nor an array; reported once, at the first item
    offending[#offending + 1] = { key = integers[1],
      message = "the table mixes array items and named keys (an object has named keys only, an array items only)" }
  elseif #integers > 0 and #others == 0 then
    for position, key in ipairs(integers) do
      if key ~= position then
        offending[#offending + 1] = { key = key, message = ("the items of an array must be numbered from 1 without a hole, item %d is missing"):format(position) }
        break
      end
    end
  end
  table.sort(offending, function(a, b) return tostring(a.key) < tostring(b.key) end)
  local is_array = #integers > 0 and strings == 0 and #others == 0 and #offending == 0
  return is_array and "array" or "object", offending
end

--- Deep copy of the table returned by a file, without the keys that no schema can read: a non-string key of an object,
--- an item of a table that also has named keys, an item after a hole. Each is a violation of code `type` at that key,
--- with the file as source (the schema would only see a table of the wrong type at the parent).
local function checked_copy(value, segments, depth, where, problems)
  if type(value) ~= "table" then return value end
  if depth > MERGE_DEPTH then
    error(configuration_error(where .. " is nested deeper than " .. MERGE_DEPTH .. " levels (or contains a cycle)", { file = where }), 0)
  end
  local shape, offending = shape_of(value)
  local dropped = {}
  for _, entry in ipairs(offending) do
    dropped[entry.key] = true
    segments[#segments + 1] = tostring(entry.key)
    local pointer = pointer_of(segments)
    problems[#problems + 1] = { path = dotted_of(pointer), pointer = pointer, code = "type", message = entry.message, source = where }
    segments[#segments] = nil
  end
  local result = {}
  for key, item in pairs(value) do
    if not dropped[key] and (shape == "array" or type(key) == "string") then
      segments[#segments + 1] = tostring(key)
      result[key] = checked_copy(item, segments, depth + 1, where, problems)
      segments[#segments] = nil
    end
  end
  return result
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

--- Evaluates a file of the configuration in an empty `_ENV` table and returns the table it returns.
local function evaluate(path, text)
  local chunk, message = load(text, "@" .. path, "t", {})
  if chunk == nil then
    -- The `near '...'` fragment of a syntax error quotes the text of the file, which may be a secret: keep the chunk
    -- name and the line only.
    message = tostring(message):gsub("%s+near%s.*$", "")
    error(configuration_error(("%s: %s"):format(path, message), { file = path }), 0)
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
  if options.wrap_secret ~= nil then return options.wrap_secret end
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
  if a.pointer ~= b.pointer then return a.pointer < b.pointer end
  return a.code < b.code
end

--- Whether the pointer is a secret key or a part of one.
local function at_secret(secret_pointers, pointer)
  while pointer ~= "" do
    if secret_pointers[pointer] then return true end
    pointer = pointer:match("^(.*)/[^/]*$") or ""
  end
  return false
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
    lines[#lines + 1] = ("  %s: %s [%s] (%s)%s"):format(problem.path == "" and "(root)" or problem.path, problem.message,
      problem.code, problem.source, problem.hint and ("; " .. problem.hint) or "")
  end
  return core.ConfigurationError(table.concat(lines, "\n"), { context = { violations = problems, environment = environment } })
end

--- Loads, merges and validates the configuration of the process (configuration.md). It reads files with `io` and
--- blocks: call it at boot, before the reactor runs; it never suspends.
---
--- Raises `hecate.core.ConfigurationError` for an invalid configuration (every problem found is in
--- `context.violations`, each `{ path, pointer, code, message, source, hint? }`: `path` is dotted, `pointer` is the
--- JSON Pointer of RFC 6901), and `hecate.core.ArgumentError` for wrong options.
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
  local secret_paths, secret_pointers, leaf_of = {}, {}, {}
  for _, leaf in ipairs(leaves) do leaf_of[leaf.path] = leaf end
  for _, path in ipairs(options.secrets or {}) do
    if leaf_of[path] == nil then
      refuse(("option secrets: %s is not a declared leaf key"):format(path), { path = path })
    end
    secret_paths[path] = true
    secret_pointers[pointer_of(leaf_of[path].node.segments)] = true
  end

  -- Reserved variables: `<PREFIX>_ENV` and the `<NAME>_FILE` of each secret cannot also be the variable of a key.
  local function reserve(name, role)
    if names[name] ~= nil then
      error(configuration_error(("key %s derives the environment variable %s, which is reserved for %s"):format(
        names[name], name, role), { variable = name }), 0)
    end
  end
  reserve(prefix .. "_ENV", "the name of the environment")
  for _, leaf in ipairs(leaves) do
    if secret_paths[leaf.path] then reserve(leaf.name .. "_FILE", "the secret file of " .. leaf.path) end
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
      environment = "production"
    end
  end

  -- Layers 2 and 3: files.
  local merged, sources, problems = {}, {}, {}
  local function layer_file(name, required)
    local path = join(directory, name)
    local text, message, missing = read_file(path)
    if text == nil then
      if missing and not required then return end
      error(configuration_error(("cannot read %s: %s"):format(path, tostring(message)), { file = path }), 0)
    end
    merge(merged, checked_copy(evaluate(path, strip_bom(text)), {}, 1, path, problems), {}, path, sources, 1, path)
  end
  layer_file("default.lua", false)
  layer_file(environment .. ".lua", explicit)

  -- How to supply a missing key: the files, the variable and, for a secret, the secret file.
  local function way_out(path)
    local hint = ("set it in %s or %s"):format(join(directory, "default.lua"), join(directory, environment .. ".lua"))
    local leaf = leaf_of[path]
    if leaf == nil then return hint end
    hint = hint .. (", or with the environment variable " .. leaf.name)
    if secret_paths[path] then hint = hint .. (" (or name a secret file in " .. leaf.name .. "_FILE)") end
    return hint
  end

  -- Records one problem. The schema message of a violation at a secret key is replaced: it may quote the value.
  local function problem(pointer, code, message, source)
    local path = dotted_of(pointer)
    local hint
    if code == "required" then
      hint = way_out(path)
    elseif at_secret(secret_pointers, pointer) then
      message = "the value of a secret key does not conform to its schema (it is not shown)"
    end
    problems[#problems + 1] = { path = path, pointer = pointer, code = code, message = message, source = source, hint = hint }
  end

  -- A coerced text: stores it or records the violations. A key that failed to coerce is not also reported missing.
  local failed = {}
  --- Whether a key that failed to coerce is `pointer` itself or lies inside it (its parent object is then absent too).
  local function covered(pointers, pointer)
    for failed_pointer in pairs(pointers) do
      if failed_pointer == pointer or failed_pointer:sub(1, #pointer + 1) == pointer .. "/" then return true end
    end
    return false
  end
  local function coerced(leaf, text, source, target)
    local ok, result = leaf.node.schema:coerce(text)
    if ok then
      set_path(target, leaf.node.segments, result)
      return
    end
    failed[pointer_of(leaf.node.segments)] = true
    for _, violation in ipairs(result) do
      problem(pointer_of(leaf.node.segments) .. violation.path, violation.code, violation.message, source)
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
        -- not `and ... or`: a boolean `false` is a value, not an absent key
        if type(node) ~= "table" then
          node = nil
          break
        end
        node = node[segment]
      end
      if node ~= nil then
        set_path(merged, leaf.node.segments, copy(node, 1, leaf.path))
        sources[pointer_of(leaf.node.segments)] = source_of[leaf.path]
        -- An ancestor that no earlier layer supplied was created here: it names this layer, not `schema default`.
        local ancestor = {}
        for i = 1, #leaf.node.segments - 1 do
          ancestor[i] = leaf.node.segments[i]
          local pointer = pointer_of(ancestor)
          if sources[pointer] == nil then sources[pointer] = source_of[leaf.path] end
        end
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
      if not named and options.secrets_directory then path = join(options.secrets_directory, leaf.name) end
      if path ~= nil then
        local text, message, missing = read_file(path)
        if text ~= nil then
          local source = "secret file " .. path
          file_source[leaf.path] = source
          coerced(leaf, strip_line_end(strip_bom(text)), source, from_files)
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
      if not (violation.code == "required" and covered(failed, violation.path)) then
        problem(violation.path, violation.code, violation.message, origin(sources, violation))
      end
    end
  else
    -- The rule that a schema cannot express (configuration.md, "Validation").
    local logging = built.logging
    local has_file = false
    for _, sink in ipairs(logging.sinks) do has_file = has_file or sink == "file" end
    if has_file and (logging.file == nil or logging.file.path == nil) then
      problem("/logging/file/path", "required", "the property is required when logging.sinks contains file", "-")
    end
  end
  if #problems > 0 then
    table.sort(problems, by_path)
    error(report(environment, problems), 0)
  end

  local frozen = values.freeze(built, wrapper_of(options), secret_paths, "", root)
  return Configuration(frozen, index, sources, environment)
end
