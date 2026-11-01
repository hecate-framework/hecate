---@diagnostic disable: need-check-nil, param-type-mismatch  -- the tests pass invalid arguments on purpose
-- The request path as the router reads it: percent-decoded per segment (RFC 3986 section 2.1: %2F is not a separator),
-- dot segments resolved (RFC 3986 section 5.2.4).
local test = require("harness.test")
local path = require("hecate.router.path")
local T = test.Case("PathTest")

local function joined(segments) return "[" .. table.concat(segments, "|") .. "]" end

function T:test_split_cuts_at_slashes_and_keeps_a_trailing_empty_segment()
  self:assert_equal("[a|b]", joined(path.split("/a/b", "strict")))
  self:assert_equal("[a|b|]", joined(path.split("/a/b/", "strict")))
  self:assert_equal("[]", joined(path.split("/", "strict")))
  self:assert_equal("[a||b]", joined(path.split("/a//b", "strict")))
end

function T:test_the_ignore_policy_drops_one_trailing_empty_segment()
  self:assert_equal("[a|b]", joined(path.split("/a/b/", "ignore")))
  self:assert_equal("[]", joined(path.split("/", "ignore")))
  self:assert_equal("[a|]", joined(path.split("/a//", "ignore")))
end

function T:test_a_root_path_is_one_empty_segment_under_the_strict_policy()
  local segments = path.split("/", "strict")
  self:assert_equal(1, #segments)
  self:assert_equal("", segments[1])
end

function T:test_each_segment_is_percent_decoded_and_an_encoded_slash_stays_inside_its_segment()
  local segments = path.split("/a%2Fb/c%20d/%C3%A9", "strict")
  self:assert_equal(3, #segments)
  self:assert_equal("a/b", segments[1])
  self:assert_equal("c d", segments[2])
  self:assert_equal("\195\169", segments[3])
end

function T:test_a_percent_sign_is_decoded_once()
  self:assert_equal("%2F", path.split("/%252F", "strict")[1])
end

function T:test_hex_digits_of_either_case_decode()
  self:assert_equal("//", path.split("/%2f%2F", "strict")[1])
end

function T:test_malformed_percent_encoding_is_refused()
  for _, raw in ipairs({ "/%", "/%2", "/%zz", "/a%g0", "/a/%2x" }) do
    local segments, reason = path.split(raw, "strict")
    self:assert_nil(segments, raw)
    self:assert_equal("malformed_percent_encoding", reason, raw)
  end
end

function T:test_an_encoded_nul_byte_is_refused()
  local segments, reason = path.split("/a%00b", "strict")
  self:assert_nil(segments)
  self:assert_equal("encoded_nul", reason)
end

function T:test_a_path_must_be_absolute()
  for _, raw in ipairs({ "", "a/b", "*", "http://h/x" }) do
    local segments, reason = path.split(raw, "strict")
    self:assert_nil(segments, raw)
    self:assert_equal("not_absolute", reason, raw)
  end
  self:assert_nil((path.split(42, "strict")))
end

function T:test_dot_segments_are_resolved_like_rfc_3986_section_5_2_4()
  local cases = {
    { "/a/b/c/./../../g", "[a|g]" },
    { "/./a", "[a]" },
    { "/a/./b", "[a|b]" },
    { "/a/b/..", "[a|]" },
    { "/a/b/.", "[a|b|]" },
    { "/a/b/../c", "[a|c]" },
    { "/a/../..", "[]" }, -- one empty segment: the root, with its trailing slash
    { "/../a", "[a]" },
    { "/..", "[]" },
    { "/.", "[]" },
    { "/a/..", "[]" },
  }
  for _, case in ipairs(cases) do
    self:assert_equal(case[2], joined(path.split(case[1], "strict")), case[1])
  end
end

function T:test_encoded_dot_segments_are_dot_segments()
  -- RFC 3986 section 6.2.2.2: percent-encoded unreserved characters are equivalent to the characters themselves.
  self:assert_equal("[a|]", joined(path.split("/a/%2e/b/%2E%2e", "strict")))
  self:assert_equal("[b]", joined(path.split("/a/%2e%2E/b", "strict")))
  self:assert_equal("[a|b]", joined(path.split("/a/%2e/b", "strict")))
end

function T:test_a_decoded_slash_never_forms_a_dot_segment()
  -- "..%2F.." is one segment whose text is "../..", not two dot segments.
  local segments = path.split("/a/..%2F..", "strict")
  self:assert_equal(2, #segments)
  self:assert_equal("../..", segments[2])
  -- "%252e%252e" decodes once, to the text "%2e%2e".
  self:assert_equal("%2e%2e", path.split("/%252e%252e", "strict")[1])
end

function T:test_dots_inside_longer_segments_are_plain_text()
  self:assert_equal("[...|.a|a.|..a]", joined(path.split("/.../.a/a./..a", "strict")))
end

function T:test_the_trailing_slash_after_resolution_follows_the_policy()
  self:assert_equal("[a]", joined(path.split("/a/b/..", "ignore")))
end

function T:test_encode_keeps_unreserved_and_escapes_the_rest()
  self:assert_equal("aZ09-._~", path.encode("aZ09-._~"))
  self:assert_equal("a%20b%2Fc%25", path.encode("a b/c%"))
  self:assert_equal("%C3%A9", path.encode("\195\169"))
  self:assert_equal("a!b", path.encode("a!b", true))
  self:assert_equal("a%2Fb", path.encode("a/b", true))
end

function T:test_encode_then_decode_round_trips_every_byte()
  local all = {}
  for byte = 1, 255 do all[#all + 1] = string.char(byte) end
  local text = table.concat(all)
  self:assert_equal(text, path.decode(path.encode(text)))
  self:assert_equal(text, path.decode(path.encode(text, true)))
end

return T
