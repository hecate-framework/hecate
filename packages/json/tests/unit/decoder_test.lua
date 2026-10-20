-- json.decoder: a text received in chunks.
local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local T = test.Case("JsonDecoderTest")

function T:test_chunks_split_anywhere_decode_like_the_whole_text()
  local text = '{"a":[1,2.5,"x\\u00e9"],"b":null}'
  for cut = 0, #text do
    local decoder = json.decoder()
    decoder:feed(text:sub(1, cut)):feed(text:sub(cut + 1))
    self:assert_equal(json.encode(json.decode(text), { canonical = true }),
      json.encode(decoder:finish(), { canonical = true }))
  end
end

function T:test_size_limit_fails_while_feeding()
  local decoder = json.decoder({ max_size = 4 })
  decoder:feed("[1,")
  local err = self:assert_error(function() decoder:feed("2,3]") end)
  self:assert_true(core.is_instance_of(err, json.DecodeError))
  self:assert_equal("size_limit", err.context.reason)
end

function T:test_invalid_text_raises_at_finish_with_a_position()
  local decoder = json.decoder():feed("[1, ?]")
  local err = self:assert_error(function() decoder:finish() end)
  self:assert_equal("syntax", err.context.reason)
  self:assert_equal(4, err.context.offset)
end

function T:test_a_finished_decoder_cannot_be_reused()
  local decoder = json.decoder():feed("1")
  self:assert_equal(1, decoder:finish())
  self:assert_error(function() decoder:feed("2") end)
  self:assert_error(function() decoder:finish() end)
end

function T:test_arguments_are_checked()
  self:assert_error(function() json.decoder({ bogus = 1 }) end)
  self:assert_error(function() json.decoder():feed(1) end)
end

return T
