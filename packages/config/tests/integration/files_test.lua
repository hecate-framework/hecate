---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field
-- Integration: `config.load` with its default `read_file` on real files (configuration.md, "Files" and "Secret files").
local test = require("harness.test")
local config = require("hecate.config")
local core = require("hecate.core")
local schema = require("hecate.schema")
local T = test.Case("ConfigFilesIntegrationTest")

local created = {}
local is_windows = package.config:sub(1, 1) == "\\"

--- A fresh, unique base path in the temporary directory of the platform (no file exists at it).
local function base()
  local name = os.tmpname()
  os.remove(name)
  created[#created + 1] = name
  return name:gsub("\\", "/")
end

local function write(path, text)
  local file = assert(io.open(path, "wb"))
  file:write(text)
  file:close()
  created[#created + 1] = path
end

local function make_directory(path)
  local quoted = is_windows and ('"' .. path:gsub("/", "\\") .. '"') or ("'" .. path .. "'")
  assert(os.execute("mkdir " .. quoted .. (is_windows and " >nul 2>&1" or " 2>/dev/null")))
  created[#created + 1] = path
end

function T:tear_down()
  for index = #created, 1, -1 do os.remove(created[index]) end
  created = {}
end

local function properties()
  return {
    name = schema.default(schema.string(), "app"),
    database = schema.default(schema.object({
      port = schema.default(schema.integer(), 5432),
      password = schema.optional(schema.string()),
    }), {}),
  }
end

local function load(directory, extra)
  local options = { properties = properties(), directory = directory, getenv = function() return nil end }
  for key, value in pairs(extra or {}) do options[key] = value end
  return config.load(options)
end

function T:test_a_default_file_with_crlf_line_ends_is_read()
  local directory = base()
  make_directory(directory)
  write(directory .. "/default.lua", "return {\r\n  name = 'crlf',\r\n  database = { port = 6000 },\r\n}\r\n")
  local configuration = load(directory)
  self:assert_equal("crlf", configuration:get("name"))
  self:assert_equal(6000, configuration:get("database.port"))
  self:assert_equal(directory .. "/default.lua", configuration:source("name"))
end

function T:test_a_default_file_with_a_byte_order_mark_is_read()
  local directory = base()
  make_directory(directory)
  write(directory .. "/default.lua", "\239\187\191return { name = 'bom' }")
  self:assert_equal("bom", load(directory):get("name"))
end

function T:test_a_trailing_separator_of_the_directory_is_not_doubled()
  local directory = base()
  make_directory(directory)
  write(directory .. "/default.lua", "return { name = 'slash' }")
  local configuration = load(directory .. "/")
  self:assert_equal("slash", configuration:get("name"))
  self:assert_equal(directory .. "/default.lua", configuration:source("name"))
end

function T:test_missing_implicit_files_are_empty()
  local directory = base()
  make_directory(directory)
  self:assert_equal("app", load(directory):get("name"))
  self:assert_equal("app", load(base() .. "-absent-directory"):get("name"))
end

function T:test_a_missing_explicit_environment_file_is_an_error()
  local directory = base()
  make_directory(directory)
  write(directory .. "/default.lua", "return {}")
  local ok, err = pcall(load, directory, { environment = "staging" })
  self:assert_false(ok)
  self:assert_true(core.is_instance_of(err, core.ConfigurationError), tostring(err))
  self:assert_true(tostring(err):find("staging.lua", 1, true) ~= nil, tostring(err))
  local via_variable, err2 = pcall(load, directory, { getenv = function(name) if name == "HECATE_ENV" then return "staging" end end })
  self:assert_false(via_variable)
  self:assert_true(tostring(err2):find("staging.lua", 1, true) ~= nil, tostring(err2))
end

function T:test_a_directory_in_place_of_a_file_is_an_error_with_a_message()
  if is_windows then return end -- opening a directory fails at `io.open` on Windows, with its own message
  local directory = base()
  make_directory(directory)
  make_directory(directory .. "/default.lua")
  local ok, err = pcall(load, directory)
  self:assert_false(ok)
  self:assert_true(core.is_instance_of(err, core.ConfigurationError), tostring(err))
  self:assert_equal(directory .. "/default.lua", err.context.file)
  self:assert_nil(tostring(err):find(": nil", 1, true), tostring(err))
  self:assert_true(tostring(err):lower():find("directory", 1, true) ~= nil, tostring(err))
end

function T:test_a_secret_file_with_crlf_is_stripped_of_one_line_end()
  local directory = base()
  make_directory(directory)
  write(directory .. "/HECATE_DATABASE__PASSWORD", "hunter2\r\n")
  local configuration = load(base(), { secrets = { "database.password" }, secrets_directory = directory })
  self:assert_equal("hunter2", configuration:get("database.password"):reveal())
end

function T:test_a_secret_file_with_a_byte_order_mark_is_read_without_it()
  local directory = base()
  make_directory(directory)
  write(directory .. "/HECATE_DATABASE__PASSWORD", "\239\187\191hunter2\n")
  local configuration = load(base(), { secrets = { "database.password" }, secrets_directory = directory .. "/" })
  self:assert_equal("hunter2", configuration:get("database.password"):reveal())
end

function T:test_an_unreadable_named_secret_file_is_an_error()
  local ok, err = pcall(load, base(), { secrets = { "database.password" },
    getenv = function(name) if name == "HECATE_DATABASE__PASSWORD_FILE" then return base() .. "-missing" end end })
  self:assert_false(ok)
  self:assert_true(core.is_instance_of(err, core.ConfigurationError), tostring(err))
end

return T
