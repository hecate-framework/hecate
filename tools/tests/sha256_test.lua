local test = require("harness.test")
local sha256 = require("lib.sha256")
local T = test.Case("Sha256Test")

function T:test_known_vectors()
  self:assert_equal("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", sha256.hex(""))
  self:assert_equal("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", sha256.hex("abc"))
  self:assert_equal("248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
    sha256.hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"))
end

function T:test_a_million_a_and_the_padding_boundaries()
  self:assert_equal("cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0", sha256.hex(("a"):rep(1000000)))
  -- 55, 56, 63, 64 and 65 bytes straddle the one-block / two-block padding boundary.
  self:assert_equal("9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318", sha256.hex(("a"):rep(55)))
  self:assert_equal("b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a", sha256.hex(("a"):rep(56)))
  self:assert_equal("ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb", sha256.hex(("a"):rep(64)))
end

return T
