local test = require("harness.test")
---@diagnostic disable-next-line: different-requires
local digest = require("hecate.cli.digest")
local T = test.Case("CliDigestTest")

local VECTORS = {
  { "", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" },
  { "abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" },
}

-- Run every backend through the same contract. A rock that is not installed skips its backend locally; CI installs
-- the `digest` rock, so there an absence is a failure.
local function contract(self, module_name, required)
  local ok, backend = pcall(require, "hecate.cli.internal." .. module_name)
  if not ok then
    if required and os.getenv("CI") then self:fail("backend " .. module_name .. " is not installed in CI: " .. tostring(backend)) end
    return
  end
  local d = digest.using(backend)
  for index, vector in ipairs(VECTORS) do
    self:assert_equal(vector[2], d.sha256(vector[1]), module_name .. " vector " .. index)
  end
  local path = os.tmpname()
  local file = assert(io.open(path, "wb"))
  file:write("abc")
  file:close()
  self:assert_equal(VECTORS[2][2], d.sha256_file(path))
  os.remove(path)
  local missing, message = d.sha256_file(path)
  self:assert_nil(missing)
  self:assert_true(type(message) == "string")
  self:assert_equal(64, #d.sha256(string.rep("x", 70000)))
  self:assert_true(d.sha256("abc"):match("^%x+$") ~= nil)
end

function T:test_digest_backend_honours_the_contract() contract(self, "digest_backend_digest", true) end

function T:test_the_default_interface_uses_an_installed_backend()
  self:assert_equal("digest", digest.backend_name)
  self:assert_equal(VECTORS[2][2], digest.sha256("abc"))
  ---@diagnostic disable-next-line: param-type-mismatch
  self:assert_error(function() digest.sha256(3) end)
end

function T:test_no_installed_backend_gives_an_actionable_error()
  local selector = require("hecate.cli.internal.digest_backend")
  local saved = selector.CANDIDATES
  selector.CANDIDATES = { "digest_backend_missing" }
  local ok, err = pcall(selector.select)
  selector.CANDIDATES = saved
  self:assert_false(ok)
  self:assert_true(tostring(err):find("luarocks install digest", 1, true) ~= nil)
end

return T
