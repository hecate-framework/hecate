-- SHA-512 (FIPS 180-4) in plain Lua 5.5 integers, so that `check-vendored` verifies the `dist.integrity` of an npm
-- tarball (`sha512-<base64>`) on every platform without depending on `openssl`, `sha512sum` or `certutil`. Standard
-- library only. The 64-bit words are Lua integers, whose arithmetic wraps modulo 2^64 and whose `>>` is logical.
local M = {}

local K = {
  0x428a2f98d728ae22, 0x7137449123ef65cd,
  0xb5c0fbcfec4d3b2f, 0xe9b5dba58189dbbc,
  0x3956c25bf348b538, 0x59f111f1b605d019,
  0x923f82a4af194f9b, 0xab1c5ed5da6d8118,
  0xd807aa98a3030242, 0x12835b0145706fbe,
  0x243185be4ee4b28c, 0x550c7dc3d5ffb4e2,
  0x72be5d74f27b896f, 0x80deb1fe3b1696b1,
  0x9bdc06a725c71235, 0xc19bf174cf692694,
  0xe49b69c19ef14ad2, 0xefbe4786384f25e3,
  0x0fc19dc68b8cd5b5, 0x240ca1cc77ac9c65,
  0x2de92c6f592b0275, 0x4a7484aa6ea6e483,
  0x5cb0a9dcbd41fbd4, 0x76f988da831153b5,
  0x983e5152ee66dfab, 0xa831c66d2db43210,
  0xb00327c898fb213f, 0xbf597fc7beef0ee4,
  0xc6e00bf33da88fc2, 0xd5a79147930aa725,
  0x06ca6351e003826f, 0x142929670a0e6e70,
  0x27b70a8546d22ffc, 0x2e1b21385c26c926,
  0x4d2c6dfc5ac42aed, 0x53380d139d95b3df,
  0x650a73548baf63de, 0x766a0abb3c77b2a8,
  0x81c2c92e47edaee6, 0x92722c851482353b,
  0xa2bfe8a14cf10364, 0xa81a664bbc423001,
  0xc24b8b70d0f89791, 0xc76c51a30654be30,
  0xd192e819d6ef5218, 0xd69906245565a910,
  0xf40e35855771202a, 0x106aa07032bbd1b8,
  0x19a4c116b8d2d0c8, 0x1e376c085141ab53,
  0x2748774cdf8eeb99, 0x34b0bcb5e19b48a8,
  0x391c0cb3c5c95a63, 0x4ed8aa4ae3418acb,
  0x5b9cca4f7763e373, 0x682e6ff3d6b2b8a3,
  0x748f82ee5defb2fc, 0x78a5636f43172f60,
  0x84c87814a1f0ab72, 0x8cc702081a6439ec,
  0x90befffa23631e28, 0xa4506cebde82bde9,
  0xbef9a3f7b2c67915, 0xc67178f2e372532b,
  0xca273eceea26619c, 0xd186b8c721c0c207,
  0xeada7dd6cde0eb1e, 0xf57d4f7fee6ed178,
  0x06f067aa72176fba, 0x0a637dc5a2c898a6,
  0x113f9804bef90dae, 0x1b710b35131c471b,
  0x28db77f523047d84, 0x32caab7b40c72493,
  0x3c9ebe0a15c9bebc, 0x431d67c49c100d4c,
  0x4cc5d4becb3e42b6, 0x597f299cfc657e2a,
  0x5fcb6fab3ad6faec, 0x6c44198c4a475817,
}

local H0 = {
  0x6a09e667f3bcc908, 0xbb67ae8584caa73b,
  0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1,
  0x510e527fade682d1, 0x9b05688c2b3e6c1f,
  0x1f83d9abfb41bd6b, 0x5be0cd19137e2179,
}

local function rotr(x, n) return (x >> n) | (x << (64 - n)) end

--- The SHA-512 digest of `data` as 64 raw bytes.
---@param data string
---@return string
function M.digest(data)
  local h0, h1, h2, h3, h4, h5, h6, h7 = table.unpack(H0)
  local length = #data
  -- 0x80, zeros up to 112 mod 128, then the 128-bit big-endian bit length (the high 64 bits of it are 0 or the carry).
  local padding = (111 - length) % 128
  data = data .. "\128" .. ("\0"):rep(padding) .. string.pack(">I8I8", length >> 61, length << 3)
  local w = {}
  for block = 1, #data, 128 do
    for i = 0, 15 do w[i] = string.unpack(">i8", data, block + i * 8) end
    for i = 16, 79 do
      local a, b = w[i - 15], w[i - 2]
      local s0 = rotr(a, 1) ~ rotr(a, 8) ~ (a >> 7)
      local s1 = rotr(b, 19) ~ rotr(b, 61) ~ (b >> 6)
      w[i] = w[i - 16] + s0 + w[i - 7] + s1
    end
    local a, b, c, d, e, f, g, h = h0, h1, h2, h3, h4, h5, h6, h7
    for i = 0, 79 do
      local s1 = rotr(e, 14) ~ rotr(e, 18) ~ rotr(e, 41)
      local ch = (e & f) ~ (~e & g)
      local t1 = h + s1 + ch + K[i + 1] + w[i]
      local s0 = rotr(a, 28) ~ rotr(a, 34) ~ rotr(a, 39)
      local maj = (a & b) ~ (a & c) ~ (b & c)
      local t2 = s0 + maj
      h, g, f, e, d, c, b, a = g, f, e, d + t1, c, b, a, t1 + t2
    end
    h0, h1, h2, h3, h4, h5, h6, h7 = h0 + a, h1 + b, h2 + c, h3 + d, h4 + e, h5 + f, h6 + g, h7 + h
  end
  return string.pack(">i8i8i8i8i8i8i8i8", h0, h1, h2, h3, h4, h5, h6, h7)
end

--- The SHA-512 digest of `data` as 128 lowercase hexadecimal digits.
---@param data string
---@return string
function M.hex(data) return (M.digest(data):gsub(".", function(c) return ("%02x"):format(c:byte()) end)) end

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

--- Standard base64 (RFC 4648, with padding) of a byte string.
---@param data string
---@return string
function M.base64(data)
  local out = {}
  for i = 1, #data, 3 do
    local a, b, c = data:byte(i, i + 2)
    local n = (a << 16) | ((b or 0) << 8) | (c or 0)
    local chars = {}
    for shift = 18, 0, -6 do
      local index = (n >> shift) & 63
      chars[#chars + 1] = ALPHABET:sub(index + 1, index + 1)
    end
    if not b then chars[3], chars[4] = "=", "=" elseif not c then chars[4] = "=" end
    out[#out + 1] = table.concat(chars)
  end
  return table.concat(out)
end

--- The Subresource Integrity string npm records as `dist.integrity`: `sha512-` and the base64 of the digest.
---@param data string
---@return string
function M.integrity(data) return "sha512-" .. M.base64(M.digest(data)) end

return M
