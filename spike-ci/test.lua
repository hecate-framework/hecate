-- Smoke test of the OQ-4/5/6 spike modules; run from the directory holding the modules.
local ext = package.config:sub(1, 1) == "\\" and "dll" or "so"
package.cpath = "./?." .. ext .. ";" .. package.cpath
local function check(name, cond) print((cond and "ok   " or "FAIL ") .. name); if not cond then os.exit(1) end end
local http = require("llhttp_lua")
local r = http("POST /p?x=1 HTTP/1.1\r\nHost: a\r\nContent-Length: 5\r\n\r\nhello")
check("llhttp parses a request", r and r.method == "POST" and r.target == "/p?x=1" and r.body == "hello" and #r.headers == 2)
check("llhttp rejects CL+TE", http("POST / HTTP/1.1\r\nContent-Length: 5\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n") == nil)
local yy = require("yy")
local v = yy('{"a":[1,2.5,"x"],"b":9007199254740993}')
check("yyjson decodes with exact integers", v.a[1] == 1 and math.type(v.a[1]) == "integer" and v.b == 9007199254740993)
check("yyjson rejects NaN", yy("NaN") == nil)
local tls = require("hecate_tls")
local echoed, rounds = tls.selftest("hello tls")
check("rustls in-memory handshake and round trip", echoed == "hello tls" and rounds >= 1)
local js = require("hecate_json")
check("serde_json encodes", js.serde_encode({ a = { 1, 2 } }) == '{"a":[1,2]}')
check("serde_json decode keeps integers", math.type(js.serde_decode("42")) == "integer")
check("sonic-rs / simd-json decode", js.sonic_decode("[1]")[1] == 1 and js.simd_decode("[1]")[1] == 1)
print("all spike modules work on Lua " .. _VERSION)
