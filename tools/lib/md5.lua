-- MD5 (RFC 1321) in plain Lua 5.5, for the `md5sums` file of a Debian package (dpkg verifies installed files with it; it
-- is not used for anything that needs collision resistance). Standard library only.
local M = {}

local S = {
  7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
  5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
  4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
  6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
}

local K = {}
for i = 0, 63 do K[i + 1] = math.floor(math.abs(math.sin(i + 1)) * 4294967296) & 0xFFFFFFFF end

local function rotate_left(x, n) return ((x << n) | (x >> (32 - n))) & 0xFFFFFFFF end

--- The MD5 digest of `data` as 32 lowercase hexadecimal digits.
---@param data string
---@return string
function M.hex(data)
  local a0, b0, c0, d0 = 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476
  local length = #data
  local padded = data .. "\128" .. ("\0"):rep((55 - length) % 64) .. string.pack("<I8", length * 8)
  local words = {}
  for block = 1, #padded, 64 do
    for i = 1, 16 do words[i] = string.unpack("<I4", padded, block + (i - 1) * 4) end
    local a, b, c, d = a0, b0, c0, d0
    for i = 0, 63 do
      local f, g
      if i < 16 then
        f, g = (b & c) | (~b & d), i
      elseif i < 32 then
        f, g = (d & b) | (~d & c), (5 * i + 1) % 16
      elseif i < 48 then
        f, g = b ~ c ~ d, (3 * i + 5) % 16
      else
        f, g = c ~ (b | (~d & 0xFFFFFFFF)), (7 * i) % 16
      end
      f = (f + a + K[i + 1] + words[g + 1]) & 0xFFFFFFFF
      a, d, c = d, c, b
      b = (b + rotate_left(f, S[i + 1])) & 0xFFFFFFFF
    end
    a0, b0, c0, d0 = (a0 + a) & 0xFFFFFFFF, (b0 + b) & 0xFFFFFFFF, (c0 + c) & 0xFFFFFFFF, (d0 + d) & 0xFFFFFFFF
  end
  return (string.pack("<I4I4I4I4", a0, b0, c0, d0):gsub(".", function(c) return ("%02x"):format(c:byte()) end))
end

return M
