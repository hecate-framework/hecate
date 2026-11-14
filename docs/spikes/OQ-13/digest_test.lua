-- Contract test: the same expectations for every backend.
--   lua digest_test.lua plc|hmac|digest     (paths of the installed rocks in LUA_PATH / LUA_CPATH)
local name = assert(arg[1], "backend name expected")
package.loaded["digest_backend"] = require("digest_backend_" .. name)
local digest = require("cli_digest")

local vectors = {
  { "", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" },
  { "abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" },
  { string.rep("a", 1000000), "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0" },
}
for i, v in ipairs(vectors) do
  local got = digest.sha256(v[1])
  assert(got == v[2], ("vector %d: %s"):format(i, got))
end

local path = os.tmpname()
local f = assert(io.open(path, "wb")); f:write("abc"); f:close()
assert(digest.sha256_file(path) == vectors[2][2], "file")
os.remove(path)
assert(digest.sha256_file(path) == nil, "missing file returns nil")
print(("ok: %s, %d vectors and the file helper"):format(digest.backend_name, #vectors))
