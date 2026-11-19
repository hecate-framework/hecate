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

function T:test_non_ascii_bytes_and_nul_bytes_are_hashed_as_bytes()
  -- UTF-8 text with 2-, 3- and 4-byte sequences.
  self:assert_equal("7da315346469d8c9f54a2ec079030708e37fccd52d769940230cba1b70ef8165",
    sha256.hex("h\xc3\xa9llo w\xc3\xb6rld \xe2\x82\xac \xf0\x9f\x98\x80"))
  self:assert_equal("6e340b9cffb37a989ca544e6bb780a2c78901d3fb33738768511a30617afa01d", sha256.hex("\0"))
  self:assert_equal("59b271ae1bbcb1d31d41929817f4b16fb439eb4f31520b5ad1d5ce98920a7138", sha256.hex("a\0b"))
  self:assert_equal("f5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b", sha256.hex(("\0"):rep(64)))
  self:assert_equal("14f825b2bbc32dd8d196367fa8776873069c12a8954d8da7513aa7704ddd09eb", sha256.hex("x\0"))
  local all = {}
  for byte = 0, 255 do all[#all + 1] = string.char(byte) end
  self:assert_equal("40aff2e9d2d8922e47afd4648e6967497158785fbd1da870e7110266bf944880", sha256.hex(table.concat(all)))
  self:assert_equal("a3d130897bc665af64f695e06f13a3796a34213a79ecbcb5bf6ef03c18bf62f5", sha256.hex(("\0"):rep(119) .. "\xff"))
end

function T:test_the_padding_boundary_of_the_second_block()
  -- The padding adds at least 9 bytes (0x80 and the 8-byte length): 119 bytes still fit in two blocks, 120 need three
  -- (the boundary of the first test is 55 and 56 for one and two). 111, 112, 127 and 128 are the neighbouring cases.
  local expected = {
    [111] = "6374f73208854473827f6f6a3f43b1f53eaa3b82c21c1a6d69a2110b2a79baad",
    [112] = "f54353008a2553262ecdc4a34749563ba0950e8b0fc8652780b0a614b99683c1",
    [119] = "31eba51c313a5c08226adf18d4a359cfdfd8d2e816b13f4af952f7ea6584dcfb",
    [120] = "2f3d335432c70b580af0e8e1b3674a7c020d683aa5f73aaaedfdc55af904c21c",
    [127] = "c57e9278af78fa3cab38667bef4ce29d783787a2f731d4e12200270f0c32320a",
    [128] = "6836cf13bac400e9105071cd6af47084dfacad4e5e302c94bfed24e013afb73e",
  }
  for length, digest in pairs(expected) do self:assert_equal(digest, sha256.hex(("a"):rep(length)), tostring(length)) end
end

return T
