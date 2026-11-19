local test = require("harness.test")
local sha512 = require("lib.sha512")
local T = test.Case("Sha512Test")

function T:test_known_vectors()
  self:assert_equal("cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e",
    sha512.hex(""))
  self:assert_equal("ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
    sha512.hex("abc"))
  self:assert_equal("8e959b75dae313da8cf4f72814fc143f8f7779c6eb9f7fa17299aeadb6889018501d289e4900f7e4331b99dec4b5433ac7d329eeb6dd26545e96e55b874be909",
    sha512.hex("abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu"))
  self:assert_equal(64, #sha512.digest("abc"))
end

function T:test_the_padding_boundaries_and_bytes()
  -- 111 bytes are the longest message whose padding fits in one block; 112 need a second one.
  local expected = {
    [111] = "fa9121c7b32b9e01733d034cfc78cbf67f926c7ed83e82200ef86818196921760b4beff48404df811b953828274461673c68d04e297b0eb7b2b4d60fc6b566a2",
    [112] = "c01d080efd492776a1c43bd23dd99d0a2e626d481e16782e75d54c2503b5dc32bd05f0f1ba33e568b88fd2d970929b719ecbb152f58f130a407c8830604b70ca",
    [119] = "130396a75cb483f2eee8c56d8a668bb3d2641f5243212c0bee2bd33da096ad9eb8179fe18f9eaacf76e09fae9de4c3f14ba13341e345be05bf76c182cc3468cb",
    [127] = "828613968b501dc00a97e08c73b118aa8876c26b8aac93df128502ab360f91bab50a51e088769a5c1eff4782ace147dce3642554199876374291f5d921629502",
    [128] = "b73d1929aa615934e61a871596b3f3b33359f42b8175602e89f7e06e5f658a243667807ed300314b95cacdd579f3e33abdfbe351909519a846d465c59582f321",
    [129] = "4f681e0bd53cda4b5a2041cc8a06f2eabde44fb16c951fbd5b87702f07aeab611565b19c47fde30587177ebb852e3971bbd8d3fd30da18d71037dfbd98420429",
    [1000] = "67ba5535a46e3f86dbfbed8cbbaf0125c76ed549ff8b0b9e03e0c88cf90fa634fa7b12b47d77b694de488ace8d9a65967dc96df599727d3292a8d9d447709c97",
  }
  for length, digest in pairs(expected) do self:assert_equal(digest, sha512.hex(("a"):rep(length)), tostring(length)) end
  local all = { "\0" }
  for byte = 0, 255 do all[#all + 1] = string.char(byte) end
  self:assert_equal("4c9911ddfc14aaf31ab42fc8b75537549eeea791a1ef9a12a3e6bdc3fbc0a9adef0192391f3edf78e39acfcc5f8431b39676c6a6bafff8cc0dba5f5322182107",
    sha512.hex(table.concat(all)))
end

function T:test_base64_and_the_integrity_string_of_npm()
  self:assert_equal("", sha512.base64(""))
  self:assert_equal("Zg==", sha512.base64("f"))
  self:assert_equal("Zm8=", sha512.base64("fo"))
  self:assert_equal("Zm9v", sha512.base64("foo"))
  self:assert_equal("Zm9vYg==", sha512.base64("foob"))
  self:assert_equal("Zm9vYmE=", sha512.base64("fooba"))
  self:assert_equal("Zm9vYmFy", sha512.base64("foobar"))
  self:assert_equal("/+8A", sha512.base64("\xff\xef\x00"))
  self:assert_equal("sha512-z4PhNX7vuL3xVChQ1m2AB9Yg5AULVxXcg/SpIdNs6c5H0NE8XYXysP+DGNKHfuwvY7kxvUdBeoGlODJ6+SfaPg==",
    sha512.integrity(""))
  self:assert_equal("sha512-1vZEsZgS6XtdhxZY1tNADs1Hh/rrm4mQwedggohmS+dyVxBKWNAzvPGg4JRf8GRo6+U+Lf824khCTHJzEX2sCQ==",
    sha512.integrity(("a"):rep(3)))
end

return T
