-- `json.set_max_depth`: the process-wide default depth, lowering only (OQ-101).
local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local T = test.Case("JsonMaxDepthTest")

function T:tear_down() json.set_max_depth(json.MAX_DEPTH_CEILING) end

function T:test_lowers_the_default_and_reads_it_back()
  json.set_max_depth(3)
  self:assert_equal(json.DEFAULT_MAX_DEPTH, 3)
end

function T:test_decode_uses_the_lowered_default()
  json.set_max_depth(2)
  self:assert_true(json.decode("[[1]]") ~= nil)
  local err = self:assert_error(function() return json.decode("[[[1]]]") end)
  self:assert_true(core.is_instance_of(err, json.DecodeError), tostring(err))
end

function T:test_an_explicit_option_still_wins()
  json.set_max_depth(2)
  self:assert_true(json.decode("[[[1]]]", { max_depth = 3 }) ~= nil)
end

function T:test_refuses_a_value_above_the_ceiling_or_not_an_integer()
  for _, bad in ipairs({ 0, -1, 1.5, "3", json.MAX_DEPTH_CEILING + 1 }) do
    local err = self:assert_error(function() json.set_max_depth(bad) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(bad))
  end
end

return T
