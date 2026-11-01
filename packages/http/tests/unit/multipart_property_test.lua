---@diagnostic disable: missing-fields, param-type-mismatch, need-check-nil  -- the tests pass invalid arguments on purpose
-- A deterministic property test of the multipart parser (the parser is pure Lua, so it is not a libFuzzer target): from a
-- seeded generator, messages that are valid and messages that are mutated are parsed whole, in random pieces and byte by
-- byte. The outcomes must agree, and the only failures allowed are `ProtocolError`s (`FormError`, `ContentError`).
local test = require("harness.test")
local core = require("hecate.core")
local http = require("hecate.http")
local multipart = require("hecate.http.multipart")
local T = test.Case("MultipartPropertyTest")

local BOUNDARY = "bnd-7f3a"

--- A linear congruential generator: the same sequence on every platform and Lua build.
local function generator(seed)
  local state = seed
  return function(n)
    state = (state * 6364136223846793005 + 1442695040888963407) & 0x7fffffffffffffff
    return (state >> 33) % n
  end
end

local FRAGMENTS = {
  "\r\n--" .. BOUNDARY, "--" .. BOUNDARY, "\r\n--" .. BOUNDARY .. "--", "\r\n--" .. BOUNDARY .. "x", "\r\n", "\r", "\n",
  "--", "\r\n\r\n", "\0", "Content-Disposition: form-data; name=\"x\"", "\255\254",
}

local function random_content(rand)
  local out = {}
  for _ = 1, rand(8) do
    if rand(3) == 0 then
      out[#out + 1] = FRAGMENTS[rand(#FRAGMENTS) + 1]
    else
      local bytes = {}
      for i = 1, rand(40) do bytes[i] = string.char(32 + rand(95)) end
      out[#out + 1] = table.concat(bytes)
    end
  end
  return table.concat(out)
end

local function random_message(rand)
  local out = { rand(2) == 0 and "preamble\r\n" or "" }
  for i = 1, rand(6) do
    local filename = rand(2) == 0 and ('; filename="f' .. i .. '.bin"') or ""
    out[#out + 1] = "--" .. BOUNDARY .. "\r\nContent-Disposition: form-data; name=\"p" .. rand(3) .. '"' .. filename
      .. (rand(2) == 0 and "\r\nContent-Type: application/octet-stream" or "") .. "\r\n\r\n"
    -- A generated content must not hold the real delimiter: a valid message stays valid.
    local content = random_content(rand)
    content = content:gsub("\r\n%-%-" .. BOUNDARY:gsub("%-", "%%-"), "\r\n-x-" .. BOUNDARY)
    -- Nor may it start with one: after the CRLF that ends the header fields it would read as a delimiter (no content).
    if content:sub(1, 2 + #BOUNDARY) == "--" .. BOUNDARY then content = "x" .. content end
    out[#out + 1] = content .. "\r\n"
  end
  out[#out + 1] = "--" .. BOUNDARY .. "--\r\n"
  return table.concat(out)
end

local function mutate(rand, text)
  for _ = 1, 1 + rand(3) do
    local kind = rand(5)
    local at = rand(#text + 1)
    if kind == 0 and #text > 0 then
      local position = 1 + rand(#text)
      text = text:sub(1, position - 1) .. string.char(rand(256)) .. text:sub(position + 1)
    elseif kind == 1 then
      text = text:sub(1, at) .. FRAGMENTS[rand(#FRAGMENTS) + 1] .. text:sub(at + 1)
    elseif kind == 2 then
      text = text:sub(1, at) .. text:sub(at + 1 + rand(20))
    elseif kind == 3 then
      text = text:sub(1, at)
    else
      text = text:sub(1, at) .. text:sub(math.max(1, at - rand(30)), at) .. text:sub(at + 1)
    end
  end
  return text
end

local function split_random(rand, text)
  local chunks, pos = {}, 1
  while pos <= #text do
    local n = 1 + rand(40)
    chunks[#chunks + 1] = text:sub(pos, pos + n - 1)
    pos = pos + n
  end
  return chunks
end

local function split_bytes(text)
  local chunks = {}
  for i = 1, #text do chunks[i] = text:sub(i, i) end
  return chunks
end

--- The outcome as a string: the parts, or the kind of the failure.
local function outcome(chunks, limits)
  local i = 0
  local source = http.ContentStream(function()
    i = i + 1
    return chunks[i]
  end)
  local result = {}
  local ok, err = pcall(function()
    local reader = multipart.Reader(source, BOUNDARY, limits)
    while true do
      local part = reader:next_part()
      if part == nil then break end
      result[#result + 1] = ("%q|%q|%q"):format(part.name, tostring(part.filename), part:read_content())
    end
  end)
  if ok then return "ok:" .. table.concat(result, "\n"), nil end
  return "error:" .. tostring(err.context and (err.context.kind or err.context.reason)), err
end

local function check(self, text, rand, limits)
  local whole, err = outcome({ text }, limits)
  if err ~= nil then
    self:assert_true(core.is_instance_of(err, core.ProtocolError), "an error that is not a ProtocolError: " .. tostring(err))
  end
  self:assert_equal(whole, (outcome(split_random(rand, text), limits)), "random pieces differ from the whole for " .. ("%q"):format(text))
  self:assert_equal(whole, (outcome(split_bytes(text), limits)), "byte by byte differs from the whole for " .. ("%q"):format(text))
  return whole
end

function T:test_valid_messages_parse_the_same_whole_and_in_pieces()
  local rand = generator(20261101)
  for _ = 1, 150 do
    local text = random_message(rand)
    local result = check(self, text, rand)
    self:assert_equal("ok:", result:sub(1, 3), "a generated message must be valid: " .. result .. " for " .. ("%q"):format(text))
  end
end

function T:test_mutated_messages_agree_and_only_fail_with_protocol_errors()
  local rand = generator(7)
  local failures, successes = 0, 0
  for _ = 1, 400 do
    local result = check(self, mutate(rand, random_message(rand)), rand)
    if result:sub(1, 5) == "error" then failures = failures + 1 else successes = successes + 1 end
  end
  self:assert_true(failures > 20 and successes > 20, ("the mutations should reach both outcomes: %d errors, %d successes"):format(failures, successes))
end

function T:test_limits_do_not_change_between_whole_and_pieces()
  local rand = generator(99)
  for _ = 1, 150 do
    check(self, mutate(rand, random_message(rand)), rand, { max_parts = 2, max_header_size = 80, max_part_size = 30 })
  end
end

return T
