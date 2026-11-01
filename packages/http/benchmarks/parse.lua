-- Throughput of the HTTP/1.1 message parser (hecate.http.parser, llhttp): requests per second for a small and a
-- browser-sized request, whole buffer and byte by byte, and for a response (needs: lua tools/run.lua build-native http).
-- Usage: lua packages/http/benchmarks/parse.lua   (from the repository root)
global <const> _VERSION, package, os, string, print, require, table, ipairs, error
package.path = "packages/http/src/?.lua;packages/http/src/?/init.lua;packages/core/src/?.lua;"
  .. "packages/core/src/?/init.lua;" .. package.path
local version = _VERSION:match("%d+%.%d+")
-- As the test harness: the project tree, then the spike tree (spikes/rocks, git-ignored), which wins.
for _, tree in ipairs({ ".hecate/rocks", "spikes/rocks" }) do
  package.cpath = tree .. "/lib/lua/" .. version .. "/?.so;" .. package.cpath
end

local Parser = require("hecate.http.parser")

local ROUNDS = 7
local SECONDS = 0.25  -- per sample

local SMALL = "GET /users/42 HTTP/1.1\r\nHost: example.org\r\n\r\n"

local BROWSER = table.concat({
  "GET /api/v1/orders?status=open&page=2 HTTP/1.1\r\n",
  "Host: shop.example.org\r\n",
  "Connection: keep-alive\r\n",
  "sec-ch-ua: \"Chromium\";v=\"126\", \"Not.A/Brand\";v=\"24\"\r\n",
  "sec-ch-ua-mobile: ?0\r\n",
  "sec-ch-ua-platform: \"Linux\"\r\n",
  "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36\r\n",
  "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8\r\n",
  "Sec-Fetch-Site: same-origin\r\n",
  "Sec-Fetch-Mode: cors\r\n",
  "Sec-Fetch-Dest: empty\r\n",
  "Referer: https://shop.example.org/orders\r\n",
  "Accept-Encoding: gzip, deflate, br, zstd\r\n",
  "Accept-Language: en-GB,en;q=0.9,fr;q=0.8\r\n",
  "Cookie: session=3f9c1d7e5b2a4c6d8e0f1a2b3c4d5e6f; theme=dark; csrf=9a8b7c6d5e4f3a2b1c0d; _ga=GA1.2.1234567890.1700000000\r\n",
  "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U\r\n",
  "If-None-Match: \"33a64df551425fcc55e4d42a148795d9f25f89d4\"\r\n",
  "\r\n",
}, "")

local RESPONSE = table.concat({
  "HTTP/1.1 200 OK\r\n",
  "Date: Sun, 01 Nov 2026 12:00:00 GMT\r\n",
  "Content-Type: application/json\r\n",
  "Content-Length: 30\r\n",
  "Cache-Control: no-store\r\n",
  "ETag: \"33a64df551425fcc55e4d42a148795d9f25f89d4\"\r\n",
  "Set-Cookie: session=3f9c1d7e5b2a4c6d8e0f1a2b3c4d5e6f; Path=/; HttpOnly; Secure; SameSite=Lax\r\n",
  "Vary: Accept-Encoding\r\n",
  "\r\n",
  "{\"id\":42,\"name\":\"first order\"}",
}, "")

local BYTES = {}
local function bytes_of(text)
  if not BYTES[text] then
    local list = {}
    for i = 1, #text do list[i] = text:sub(i, i) end
    BYTES[text] = list
  end
  return BYTES[text]
end

--- Messages per second: repeats `step` for SECONDS and divides, median of ROUNDS samples.
local function rate(step)
  local samples = {}
  step()
  for i = 1, ROUNDS do
    local count, start = 0, os.clock()
    repeat
      for _ = 1, 100 do step() end
      count = count + 100
    until os.clock() - start >= SECONDS
    samples[i] = count / (os.clock() - start)
  end
  table.sort(samples)
  return samples[(ROUNDS + 1) // 2]
end

local function whole(kind, text)
  local parser = Parser.new(kind)
  return function()
    local events, err = parser:feed(text)
    if err or #events == 0 then error("benchmark message not parsed") end
  end
end

local function by_byte(kind, text)
  local parser = Parser.new(kind)
  local list = bytes_of(text)
  return function()
    for i = 1, #list do parser:feed(list[i]) end
  end
end

local function report(label, step, size)
  local per_second = rate(step)
  print(("%s  %.0f messages/s"):format(label, per_second))
  print(("%s throughput  %.1f MB/s"):format(label, per_second * size / (1024 * 1024)))
end

report("request small whole-buffer", whole("request", SMALL), #SMALL)
report("request small byte-by-byte", by_byte("request", SMALL), #SMALL)
report("request browser whole-buffer", whole("request", BROWSER), #BROWSER)
report("request browser byte-by-byte", by_byte("request", BROWSER), #BROWSER)
report("response whole-buffer", whole("response", RESPONSE), #RESPONSE)
report("response byte-by-byte", by_byte("response", RESPONSE), #RESPONSE)
