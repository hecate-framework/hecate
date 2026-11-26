local test = require("harness.test")
local sha1 = require("lib.sha1")
local T = test.Case("Sha1Test")

function T:test_known_vectors()
  self:assert_equal("da39a3ee5e6b4b0d3255bfef95601890afd80709", sha1.hex(""))
  self:assert_equal("a9993e364706816aba3e25717850c26c9cd0d89d", sha1.hex("abc"))
  self:assert_equal("84983e441c3bd26ebaae4aa1f95129e5e54670f1",
    sha1.hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"))
end

function T:test_a_million_a_and_the_padding_boundaries()
  self:assert_equal("34aa973cd4c4daa4f61eeb2bdbad27316534016f", sha1.hex(("a"):rep(1000000)))
  -- 55, 56, 63, 64 and 65 bytes straddle the one-block / two-block padding boundary.
  local handle = io.popen("command -v sha1sum")
  local have = handle and handle:read("a") ~= ""
  if handle then handle:close() end
  if not have then return end
  for _, n in ipairs({ 55, 56, 63, 64, 65 }) do
    local path = os.tmpname()
    local f = assert(io.open(path, "wb"))
    f:write(("a"):rep(n))
    f:close()
    local p = assert(io.popen("sha1sum " .. path))
    local expected = p:read("a"):match("^%x+")
    p:close()
    os.remove(path)
    self:assert_equal(expected, sha1.hex(("a"):rep(n)), tostring(n) .. " bytes")
  end
end

return T
