---@diagnostic disable: need-check-nil, undefined-field  -- tests index generated pages that a failing assertion would reveal
-- The project documentation: API reference and route map from an OpenAPI document, the
-- configuration reference from a JSON Schema, and the site that `project.build` writes.
local test = require("harness.test")
local doc = require("hecate.doc")
local project = require("hecate.doc.project")
local T = test.Case("ProjectTest")

local document = {
  openapi = "3.1.0",
  info = { title = "Shop", version = "1.2.0", description = "The shop API." },
  tags = { { name = "users", description = "Accounts." } },
  paths = {
    ["/users"] = {
      post = {
        operationId = "createUser", summary = "Create a user", tags = { "users" },
        requestBody = { required = true, content = { ["application/json"] = { schema = { ["$ref"] = "#/components/schemas/User" } } } },
        responses = {
          ["201"] = { description = "Created", content = { ["application/json"] = { schema = { ["$ref"] = "#/components/schemas/User" } } } },
          ["422"] = { description = "Unprocessable Content" },
        },
      },
    },
    ["/users/{id}"] = {
      get = {
        operationId = "getUser", summary = "Fetch a user", description = "Fetch one.", tags = { "users" }, deprecated = true,
        parameters = { { name = "id", ["in"] = "path", required = true, schema = { type = "integer", minimum = 1 } } },
        responses = { ["200"] = { description = "OK" } },
      },
    },
    ["/health"] = { get = { operationId = "health", responses = { ["200"] = { description = "OK" } } } },
  },
  components = { schemas = { User = { type = "object", required = { "name" },
    properties = { name = { type = "string", description = "Display name." }, age = { type = "integer" } } } } },
}

local config_schema = {
  type = "object", required = { "port" },
  properties = {
    port = { type = "integer", minimum = 1, maximum = 65535, description = "TCP port." },
    mode = { type = "string", enum = { "dev", "prod" }, default = "dev" },
    database = { type = "object", properties = { url = { type = "string", description = "Connection URL." } } },
  },
}

function T:test_api_pages_cover_every_operation_and_the_route_map()
  local pages = project.api_pages(document)
  self:assert_not_nil(pages["api/index.md"])
  self:assert_not_nil(pages["api/users.md"])
  self:assert_not_nil(pages["api/untagged-operations.md"])
  local index = pages["api/index.md"]
  self:assert_not_nil(index:find("| `POST` | `/users` | [createUser](users.md#createuser) |", 1, true), index)
  self:assert_not_nil(index:find("`/health`", 1, true))
  local users = pages["api/users.md"]
  self:assert_not_nil(users:find("## getUser", 1, true))
  self:assert_not_nil(users:find("Deprecated", 1, true))
  self:assert_not_nil(users:find("`id`", 1, true))
  self:assert_not_nil(users:find("`422`", 1, true))
  self:assert_not_nil(users:find("`name`", 1, true), "the schema reference is resolved")
end

function T:test_pages_are_marked_as_generated_and_deterministic()
  local first, second = project.api_pages(document), project.api_pages(document)
  for path, text in pairs(first) do
    self:assert_equal(text, second[path], path)
    self:assert_true(project.is_generated(text), path)
  end
end

function T:test_configuration_page_lists_keys_with_dotted_paths()
  local page = project.configuration_page(config_schema)
  self:assert_not_nil(page:find("`port`", 1, true))
  self:assert_not_nil(page:find("`database.url`", 1, true))
  self:assert_not_nil(page:find("required", 1, true))
  self:assert_not_nil(page:find("`dev`", 1, true))
  self:assert_not_nil(page:find("1 to 65535", 1, true), page)
end

function T:test_text_from_the_contract_cannot_break_the_table()
  local nasty = { openapi = "3.1.0", info = { title = "T", version = "1" }, paths = { ["/a|b"] = { get = { operationId = "x|y",
    summary = "line1\nline2 | pipe", responses = { ["200"] = { description = "OK" } } } } } }
  local index = project.api_pages(nasty)["api/index.md"]
  for line in index:gmatch("[^\n]+") do
    if line:find("^| `GET`") then
      local _, pipes = line:gsub("\\|", "")
      local _, all = line:gsub("|", "")
      self:assert_equal(5, all - pipes, line)
    end
  end
end

function T:test_build_writes_a_site_with_all_sections()
  local fs = doc.MemoryFileSystem({})
  local report = project.build({
    config = { title = "Shop docs" }, source = "docs", out = "dist", fs = fs, clean = true, strict = true,
    document = document, configuration = config_schema,
    pages = { ["index.md"] = "# Shop\n\nWelcome.\n" },
  })
  self:assert_equal(0, #report.problems, table.concat(report.problems, "\n"))
  self:assert_not_nil(fs:read("dist/en/api/users/index.html"))
  self:assert_not_nil(fs:read("dist/en/configuration/index.html"))
  self:assert_not_nil(fs:read("dist/en/index.html"))
end

function T:test_build_reports_the_code_reference_of_the_project()
  local fs = doc.MemoryFileSystem({})
  local report = project.build({
    config = { title = "Shop docs" }, source = "docs", out = "dist", fs = fs,
    pages = { ["index.md"] = "# Shop\n\nWelcome.\n" },
    code = { root = "shop", name = "shop" },
  })
  self:assert_not_nil(report.code)
  if report.code.skipped then
    self:assert_equal(true, #report.problems >= 1)
  else
    self:assert_equal(0, report.code.pages) -- no src directory in the memory file system
  end
end

return T
