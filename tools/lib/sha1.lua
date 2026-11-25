-- SHA-1 (RFC 3174) in plain Lua 5.5, for the per-file checksums that an Alpine package embeds (`apk` verifies installed
-- files with it; it is not used for anything that needs collision resistance). Standard library only.
local M = {}

local MASK = 0xFFFFFFFF

local function rotate_left(x, n) return ((x << n) | (x >> (32 - n))) & MASK end

--- The SHA-1 digest of `data` as 40 lowercase hexadecimal digits.
---@param data string
---@return string
function M.hex(data)
  local h0, h1, h2, h3, h4 = 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0
  local length = #data
  local padded = data .. "\128" .. ("\0"):rep((55 - length) % 64) .. string.pack(">I8", length * 8)
  local w = {}
  for block = 1, #padded, 64 do
    for i = 0, 15 do w[i] = string.unpack(">I4", padded, block + i * 4) end
    for i = 16, 79 do w[i] = rotate_left(w[i - 3] ~ w[i - 8] ~ w[i - 14] ~ w[i - 16], 1) end
    local a, b, c, d, e = h0, h1, h2, h3, h4
    for i = 0, 79 do
      local f, k
      if i < 20 then
        f, k = (b & c) | (~b & MASK & d), 0x5A827999
      elseif i < 40 then
        f, k = b ~ c ~ d, 0x6ED9EBA1
      elseif i < 60 then
        f, k = (b & c) | (b & d) | (c & d), 0x8F1BBCDC
      else
        f, k = b ~ c ~ d, 0xCA62C1D6
      end
      local temp = (rotate_left(a, 5) + f + e + k + w[i]) & MASK
      a, b, c, d, e = temp, a, rotate_left(b, 30), c, d
    end
    h0, h1, h2, h3, h4 = (h0 + a) & MASK, (h1 + b) & MASK, (h2 + c) & MASK, (h3 + d) & MASK, (h4 + e) & MASK
  end
  return ("%08x%08x%08x%08x%08x"):format(h0, h1, h2, h3, h4)
end

return M
