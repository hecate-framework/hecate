local test = require("harness.test")
local release_version = require("lib.release_version")
local T = test.Case("ReleaseVersionTest")

local VALID = { "0.4.2-1", "1.0.0-12", "0.4.2rc1-1", "1.0.0beta2-1", "1.0.0alpha10-3", "1.0.0pre1-1", "10.20.30rc99-100" }
local INVALID = { "0.4.2-rc1-1", "0.4.2rc-1", "v0.4.2-1", "0.4.2rc1", "0.4.2", "dev-1", "scm-1", "0.4.2dev1-1", "0.4.2scm1-1",
  "0.4.2cvs1-1", "0.4.2RC1-1", "0.4.2rc1.1-1", "0.4.2rc1-1-1", "0.4.2rc1-", "0.4-1", "-1", "", "0.4.2rc1-1\n" }

function T:test_valid_and_invalid_release_versions()
  for _, v in ipairs(VALID) do self:assert_not_nil(release_version.parse(v), v) end
  for _, v in ipairs(INVALID) do self:assert_nil(release_version.parse(v), v) end
end

function T:test_base_versions_are_what_the_version_file_holds()
  self:assert_true(release_version.is_base("0.4.2"))
  self:assert_true(release_version.is_base("0.4.2rc1"))
  self:assert_false(release_version.is_base("0.4.2-1"))
  self:assert_false(release_version.is_base("0.4.2scm"))
  self:assert_false(release_version.is_prerelease("0.4.2"))
  self:assert_true(release_version.is_prerelease("0.4.2beta1"))
end

function T:test_the_tokens_are_the_ones_luarocks_orders_before_the_final_release()
  self:assert_equal("alpha beta pre rc", table.concat(release_version.PRERELEASE_TOKENS, " "))
end

function T:test_the_setup_action_uses_the_same_grammar_as_the_validator()
  local f = assert(io.open("packages/actions/setup/action.yml", "rb"))
  local text = f:read("a")
  f:close()
  local ere = release_version.ERE
  self:assert_true(text:find('=~ ' .. ere, 1, true) ~= nil, "action.yml does not use " .. ere)
  -- The shell form accepts exactly what the Lua form does: check with `bash` when it is there.
  local bash = io.popen("bash --version 2>/dev/null")
  local have_bash = bash and bash:read("a") ~= ""
  if bash then bash:close() end
  if not have_bash then return end
  for _, list in ipairs({ { VALID, true }, { INVALID, false } }) do
    for _, v in ipairs(list[1]) do
      if not v:find("\n", 1, true) then
        local p = assert(io.popen(("bash -c '[[ \"$1\" =~ %s ]] && echo yes || echo no' _ '%s'"):format(ere, v)))
        local answer = (p:read("a") or ""):gsub("%s+$", "")
        p:close()
        self:assert_equal(list[2] and "yes" or "no", answer, v)
      end
    end
  end
end

return T
