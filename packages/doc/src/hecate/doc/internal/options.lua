-- The closed lists of the options and of the keys of `site.lua`: a name that is not on its list is refused with the name
-- of its replacement when it is an old one (`internal.renamed_options`), with a close name when it looks like a typo, and
-- with the list otherwise. The project is in alpha: an old name is no alias, and a name that does nothing is a mistake the
-- caller must hear about (a misspelt `fail_on_problem` would turn a safeguard off in silence).
global <const> require, type, ipairs, pairs, table, string, error, tostring, math

local core = require("hecate.core")
local paths = require("hecate.doc.internal.paths")
local renamed = require("hecate.doc.internal.renamed_options")

local M = {}

--- The options of `hecate.doc.Site`.
M.SITE = { "site_configuration", "guides_dir", "file_system", "last_updated", "theme_file_system", "theme_files_dir",
  "other_site_audiences" }

--- The options of `hecate.doc.build`: those of `Site` and the ones of the output.
M.BUILD = { "site_configuration", "guides_dir", "file_system", "last_updated", "theme_file_system", "theme_files_dir",
  "output_dir", "clean_output_dir", "fail_on_problems" }

--- The options of `hecate.doc.generate_project_documentation`.
M.PROJECT_DOCUMENTATION = { "project_dir", "guides_dir", "output_dir", "site_configuration", "site_configuration_path",
  "application", "package_name", "sources_dir", "language_server_path", "language_server_config_path", "licences_page",
  "content_locale", "file_system", "clean_output_dir", "fail_on_problems", "last_updated", "theme_file_system",
  "theme_files_dir" }

--- The table of `licences_page` of `generate_project_documentation`.
M.LICENCES_PAGE = { "rocks_tree_dir", "root_rocks", "audience", "include_bundled" }

--- The options of `hecate.doc.licences.read`.
M.LICENCES_READ = { "rocks_tree_dir", "root_rocks", "max_rocks" }

--- The options of `hecate.doc.licences.bundled`.
M.LICENCES_BUNDLED = { "diagrams", "theme_file_system", "theme_files_dir" }

--- The options of `hecate.doc.reference_site.run`.
M.REFERENCE_SITE = { "project_dir", "packages", "locale_dir", "file_system", "language_server_path",
  "language_server_config_path", "since", "internal", "label_audiences", "separate_audience_sites", "sources_dir_pattern" }

--- The options of `hecate.doc.reference.generate`.
M.REFERENCE = { "since", "internal", "label_audiences", "separate_audience_sites", "examples", "pages_dir" }

--- The options of `hecate.doc.luals.export`.
M.LUALS_EXPORT = { "language_server_config_path", "file_system" }

--- The keys of the site configuration (`site.lua`).
M.SITE_KEYS = { "title", "description", "base_path", "site_origin", "default_locale", "locales", "top_links", "sidebar",
  "repository_url", "edit_link_template", "source_edit_link_template", "footer", "outline_levels", "interface_strings",
  "logo_path", "favicon_path", "sidebar_marker", "stylesheet_path", "generate_llms_txt", "exclude_file_names",
  "audiences", "default_audience", "audience_sites" }

-- Edit distance (Levenshtein) of two short names.
local function distance(a, b)
  local previous = {}
  for j = 0, #b do previous[j] = j end
  for i = 1, #a do
    local current = { [0] = i }
    for j = 1, #b do
      local cost = a:byte(i) == b:byte(j) and 0 or 1
      current[j] = math.min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
    end
    previous = current
  end
  return previous[#b]
end

--- The name of `list` closest to `name` (at most two edits, or a plural of it), or nil.
---@param name string
---@param list string[]
---@return string?
function M.suggest(name, list)
  local best, best_distance = nil, 3
  for _, candidate in ipairs(list) do
    local d = distance(name:lower(), candidate)
    if d < best_distance then best, best_distance = candidate, d end
  end
  return best
end

--- What to tell about a name that is not allowed: the replacement of an old name, the text of a removal, a close name.
---@param section string  key of `renamed_options.options`
---@param name string
---@param list string[]  the allowed names
---@return string
function M.hint(section, name, list)
  local entry = (renamed.options[section] or {})[name]
  if type(entry) == "string" then return ("was renamed `%s`"):format(entry) end
  if type(entry) == "table" then return "was removed: " .. entry.removed end
  local close = M.suggest(name, list)
  return "is not an option" .. (close and (" (did you mean `%s`?)"):format(close) or "")
    .. "; the options are " .. table.concat(list, ", ")
end

--- Refuses the first option of `options` (in the order of the names) that is not in `allowed`: a
--- `hecate.core.ArgumentError` whose `context.argument` is the name.
---@param who string  the function, for the message (`doc.build`)
---@param section string  key of `renamed_options.options`
---@param options table
---@param allowed string[]
---@param level? integer  `error` level of the caller's caller (default 3)
function M.check(who, section, options, allowed, level)
  local known = {}
  for _, name in ipairs(allowed) do known[name] = true end
  local unknown = {}
  for key in pairs(options) do
    if type(key) ~= "string" or not known[key] then unknown[#unknown + 1] = key end
  end
  if #unknown == 0 then return end
  table.sort(unknown, function(a, b) return tostring(a) < tostring(b) end)
  local key = unknown[1]
  local message
  if type(key) ~= "string" then
    message = ("%s: the options must be keyed by name (a string), got a key of type %s"):format(who, type(key))
  else
    message = ("%s: option `%s` %s"):format(who, key, M.hint(section, key, allowed))
  end
  error(core.ArgumentError({ message = message, context = { argument = type(key) == "string" and key or nil } }), level or 3)
end

--- Whether `value` can serve as a file system: an object with the five methods of the contract.
---@param value any
---@return boolean
function M.is_file_system(value)
  if type(value) ~= "table" then return false end
  for _, method in ipairs({ "read", "write", "exists", "list", "remove_tree" }) do
    if type(value[method]) ~= "function" then return false end
  end
  return true
end

local PATHS = { guides_dir = true, output_dir = true, project_dir = true, sources_dir = true,
  site_configuration_path = true, language_server_config_path = true, theme_files_dir = true, language_server_path = true }
local BOOLEANS = { clean_output_dir = true, fail_on_problems = true }

--- The first of `names` that holds a wrong value in `options`, with what it expects (`nil` when all is well). Only the names
--- listed are looked at; a name that is absent is right.
---@param options table
---@param names string[]
---@return string? field
---@return string? expected
function M.invalid(options, names)
  for _, name in ipairs(names) do
    local value = options[name]
    if value ~= nil then
      if PATHS[name] then
        if type(value) ~= "string" or value == "" or value:find("%z") then return name, "a non-empty path (string)" end
        if paths.is_drive_relative(value) then
          return name, "an absolute path (`C:/...`) or a relative one: `C:file` is relative to the current directory of a drive"
        end
      elseif BOOLEANS[name] then
        if type(value) ~= "boolean" then return name, "a boolean" end
      elseif name == "file_system" then
        if not M.is_file_system(value) then
          return name, "a hecate.doc.FileSystem (read, write, exists, list and remove_tree)"
        end
      elseif name == "theme_file_system" then
        if type(value) ~= "table" or type(value.read) ~= "function" then
          return name, "an object with a `read` method (a hecate.doc.FileSystem)"
        end
      elseif name == "last_updated" then
        if type(value) ~= "function" then return name, "a function (path) returning an ISO 8601 date or nil" end
      elseif name == "site_configuration" then
        if type(value) ~= "table" then return name, "a table" end
      end
    end
  end
  return nil
end

--- Raises a `hecate.core.ArgumentError` naming an option and what it expects (`context.argument` is the name).
---@param who string
---@param field string
---@param expected string
---@param level? integer
function M.refuse(who, field, expected, level)
  error(core.ArgumentError({
    message = ("%s: option `%s` must be %s"):format(who, field, expected), context = { argument = field },
  }), level or 3)
end

--- Refuses a key of the site configuration that is not in `M.SITE_KEYS`: a `hecate.core.ConfigurationError`
--- (`context.field` is the key) naming the replacement of an old key or a close key.
---@param raw table
---@param make fun(field: string, message: string)  raises the error
function M.check_site_keys(raw, make)
  local known = {}
  for _, name in ipairs(M.SITE_KEYS) do known[name] = true end
  local unknown = {}
  for key in pairs(raw) do
    if type(key) ~= "string" or not known[key] then unknown[#unknown + 1] = key end
  end
  if #unknown == 0 then return end
  table.sort(unknown, function(a, b) return tostring(a) < tostring(b) end)
  local key = unknown[1]
  if type(key) ~= "string" then make("site_configuration", "expected keys that are names (strings)") end
  local replacement = renamed.site_keys[key]
  if replacement then make(key, ("`%s` was renamed `%s`"):format(key, replacement)) end
  -- A typo of an old name (`logos`) points to the key that replaced it.
  local candidates = {}
  for _, name in ipairs(M.SITE_KEYS) do candidates[#candidates + 1] = name end
  for old in pairs(renamed.site_keys) do candidates[#candidates + 1] = old end
  table.sort(candidates)
  local close = M.suggest(key, candidates)
  close = close and renamed.site_keys[close] or close
  make(key, ("`%s` is not a key of the site configuration%s; the keys are %s"):format(key,
    close and (" (did you mean `%s`?)"):format(close) or "", table.concat(M.SITE_KEYS, ", ")))
end

return M
