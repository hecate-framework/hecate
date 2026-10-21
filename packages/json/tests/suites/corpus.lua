-- JSONTestSuite (https://github.com/nst/JSONTestSuite, MIT; downloaded by `fetch-fixtures json`): every `y_` file must
-- decode, every `n_` file must be rejected with a DecodeError, and an `i_` file (implementation-defined) must
-- either decode or raise a DecodeError, never anything else. Documented rejections of valid texts
-- (OQ-48) are listed in STRICTER.
-- Shared suite: loaded once per backend by tests/unit/corpus_<backend>_test.lua with the backend name as
-- argument (`...`).
local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local backend = require("hecate.json.internal.backend")
local backend_name = ...
local T = test.Case("JsonCorpusTest[" .. backend_name .. "]")

local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
local dir = here .. "/../../../../.hecate/fixtures/json/JSONTestSuite/test_parsing/"
local manifest = here .. "/../JSONTestSuite.manifest"

-- Valid texts that `decode` rejects on purpose.
local STRICTER = {
  ["y_object_duplicated_key.json"] = "duplicate member name",
  ["y_object_duplicated_key_and_value.json"] = "duplicate member name",
}

local function available()
  local file = io.open(dir .. "y_structure_lonely_true.json", "rb")
  if file then file:close() end
  return file ~= nil
end

function T:set_up() backend.use(backend_name) end

function T:tear_down() backend.use(nil) end

local function read(name)
  local file = assert(io.open(dir .. name, "rb"))
  local text = file:read("a")
  file:close()
  return text
end

local function names()
  local list = {}
  for name in io.lines(manifest) do list[#list + 1] = name end
  return list
end

-- Locally the corpus is optional (no network, no download yet); in CI a missing corpus is a failure.
local function present(self)
  if available() then return true end
  if os.getenv("CI") then self:fail("the JSONTestSuite corpus is missing (lua tools/run.lua fetch-fixtures json)") end
  io.stderr:write("# skipped: the JSONTestSuite corpus is missing (lua tools/run.lua fetch-fixtures json)\n")
  return false
end

function T:test_the_manifest_lists_the_corpus()
  self:assert_true(#names() >= 300)
  if not present(self) then return end
  for _, name in ipairs(names()) do self:assert_equal(true, read(name) ~= nil, name) end
end

function T:test_every_text_gets_the_expected_verdict()
  if not present(self) then return end
  for _, name in ipairs(names()) do
    local kind = name:sub(1, 2)
    local ok, result = pcall(json.decode, read(name))
    if not ok then
      self:assert_true(core.is_instance_of(result, json.DecodeError), name .. ": " .. tostring(result))
    end
    if kind == "y_" then
      if STRICTER[name] then
        self:assert_false(ok, name .. " is rejected on purpose")
      else
        self:assert_true(ok, name .. " must decode: " .. tostring(result))
      end
    elseif kind == "n_" then
      self:assert_false(ok, name .. " must be rejected")
    end
  end
end

return T
