-- Throughput of the form parsers (pure Lua): application/x-www-form-urlencoded and multipart/form-data, whole and fed in
-- chunks of 16 KiB, the size the server reads at a time.
-- Usage: lua packages/http/benchmarks/forms.lua   (from the repository root)
global <const> _VERSION, package, os, string, print, require, table, error, pairs, ipairs
package.path = "packages/http/src/?.lua;packages/http/src/?/init.lua;packages/core/src/?.lua;"
  .. "packages/core/src/?/init.lua;" .. package.path

local ContentStream = require("hecate.http.content")
local form = require("hecate.http.form")
local multipart = require("hecate.http.multipart")

local ROUNDS = 7
local SECONDS = 0.25 -- per sample

--- Operations per second: repeats `step` for SECONDS and divides, median of ROUNDS samples.
local function rate(step)
  local samples = {}
  step()
  for i = 1, ROUNDS do
    local count, start = 0, os.clock()
    repeat
      for _ = 1, 10 do step() end
      count = count + 10
    until os.clock() - start >= SECONDS
    samples[i] = count / (os.clock() - start)
  end
  table.sort(samples)
  return samples[(ROUNDS + 1) // 2]
end

local function report(label, step, size)
  local per_second = rate(step)
  print(("%s  %.0f messages/s"):format(label, per_second))
  print(("%s throughput  %.1f MB/s"):format(label, per_second * size / (1024 * 1024)))
end

-- application/x-www-form-urlencoded: 20 pairs, about 600 bytes, with percent-encoded and plus-encoded values.
local pairs_ = {}
for i = 1, 20 do pairs_[i] = { "field" .. i, "value number " .. i .. " with é & = % sign" } end
local URLENCODED = form.encode_urlencoded(pairs_)
report("urlencoded parse (20 pairs)", function() form.parse_urlencoded(URLENCODED) end, #URLENCODED)
report("urlencoded encode (20 pairs)", function() form.encode_urlencoded(pairs_) end, #URLENCODED)

-- multipart/form-data
local BOUNDARY = "----hecate-benchmark-boundary"
local function message(parts)
  local out = {}
  for _, part in ipairs(parts) do
    out[#out + 1] = "--" .. BOUNDARY .. "\r\nContent-Disposition: form-data; name=\"" .. part.name .. "\""
      .. (part.filename and ("; filename=\"" .. part.filename .. "\"") or "") .. "\r\n\r\n" .. part.content .. "\r\n"
  end
  out[#out + 1] = "--" .. BOUNDARY .. "--\r\n"
  return table.concat(out)
end

local function chunks(text, size)
  local list = {}
  for pos = 1, #text, size do list[#list + 1] = text:sub(pos, pos + size - 1) end
  return list
end

local function parse(list, limits)
  return function()
    local i = 0
    local reader = multipart.Reader(ContentStream(function()
      i = i + 1
      return list[i]
    end), BOUNDARY, limits)
    while true do
      local part = reader:next_part()
      if part == nil then break end
      part:read_content()
    end
  end
end

local SMALL = message({
  { name = "title", content = "A title" }, { name = "body", content = ("lorem ipsum "):rep(20) }, { name = "tags", content = "a,b,c" },
})
local FILE = message({ { name = "title", content = "upload" }, { name = "file", filename = "data.bin", content = ("0123456789abcdef"):rep(65536) } })

report("multipart small (3 parts) whole", parse({ SMALL }), #SMALL)
report("multipart small (3 parts) byte by byte", parse(chunks(SMALL, 1)), #SMALL)
report("multipart 1 MiB file, chunks of 16 KiB", parse(chunks(FILE, 16384), { max_part_size = 2 * 1048576, max_total_size = 2 * 1048576 }), #FILE)
