local test = require("harness.test")
local setup = require("tasks.setup_luals")
local T = test.Case("SetupLuaLSTest")

local WORKFLOW = [[
env:
  LUALS_VERSION: 3.19.1
  LUALS_PINS: |
    Linux-X64) asset=linux-x64.tar.gz; sha=aa11
    macOS-ARM64) asset=darwin-arm64.tar.gz; sha=bb22
    Windows-X64) asset=win32-x64.zip; sha=cc33
]]

function T:test_the_pin_of_every_ci_platform_is_read_from_the_workflow()
  local version, asset, sha = setup.pin(WORKFLOW, "Linux-X64")
  self:assert_equal("3.19.1", version)
  self:assert_equal("linux-x64.tar.gz", asset)
  self:assert_equal("aa11", sha)
  local _, mac_asset, mac_sha = setup.pin(WORKFLOW, "macOS-ARM64")
  self:assert_equal("darwin-arm64.tar.gz", mac_asset)
  self:assert_equal("bb22", mac_sha)
  local _, windows_asset, windows_sha = setup.pin(WORKFLOW, "Windows-X64")
  self:assert_equal("win32-x64.zip", windows_asset)
  self:assert_equal("cc33", windows_sha)
end

function T:test_the_pins_of_ci_yml_are_complete_and_sha256_digests()
  local file = assert(io.open(debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/tools/tests/") .. "/.github/workflows/ci.yml", "rb"))
  local text = file:read("a")
  file:close()
  for _, runner in ipairs({ "Linux-X64", "macOS-ARM64", "Windows-X64" }) do
    local version, asset, sha = setup.pin(text, runner)
    self:assert_not_nil(version, runner)
    self:assert_not_nil(asset, runner)
    self:assert_equal(64, #(sha or ""), runner)
  end
end

return T
