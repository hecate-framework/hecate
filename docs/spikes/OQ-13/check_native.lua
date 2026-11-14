-- Run by the host (the executable acting as the interpreter): loads a rock module and, for `digest`, checks a hash.
--   host check_native.lua <module>
local name = assert(arg[1], "module name expected")
local m = require(name)
if name == "digest" then
  local h = m.sha256hex("abc")
  assert(h == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "wrong hash: " .. tostring(h))
end
print(("ok: %s loaded in the host (%s)"):format(name, _VERSION))
