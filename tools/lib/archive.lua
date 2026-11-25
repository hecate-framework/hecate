-- Deterministic archives in plain Lua, so that `package-cli` produces the same bytes from the same files on every run
-- and every platform that has the compressor: a ustar writer (sorted entries, fixed time, owner 0, empty owner names), a
-- zip writer (stored entries, fixed DOS time, sorted) and CRC-32. The platform `tar` is not used to write (GNU tar and
-- bsdtar differ in their options and defaults); `gzip -n` compresses the tar (see `M.gzip`). Standard library only.
local util = require("lib.util")

local M = {}

--- The modification time of every entry: 1980-01-01T00:00:00Z, the earliest instant a zip can hold.
M.MTIME = 315532800

--- DOS time and date of `M.MTIME` (00:00:00, 1980-01-01).
local DOS_TIME, DOS_DATE = 0, (0 << 9) | (1 << 5) | 1

local crc_table
local function crc_init()
  crc_table = {}
  for i = 0, 255 do
    local c = i
    for _ = 1, 8 do c = (c & 1) ~= 0 and (0xEDB88320 ~ (c >> 1)) or (c >> 1) end
    crc_table[i] = c
  end
end

--- The CRC-32 (IEEE) of `data`.
---@param data string
---@return integer
function M.crc32(data)
  if not crc_table then crc_init() end
  local c = 0xFFFFFFFF
  local tbl, byte = crc_table, string.byte
  for i = 1, #data, 4096 do
    local chunk = { byte(data, i, math.min(i + 4095, #data)) }
    for j = 1, #chunk do c = tbl[(c ~ chunk[j]) & 0xFF] ~ (c >> 8) end
  end
  return c ~ 0xFFFFFFFF
end

---@class tools.ArchiveEntry
---@field name string   path inside the archive, `/`-separated, at most 100 bytes, no leading `/` or `..`
---@field data string
---@field mode? integer   permission bits, default 0644

--- The entries sorted by name; a bad or duplicate name is an error.
---@param entries tools.ArchiveEntry[]
---@return tools.ArchiveEntry[]
local function sorted(entries)
  local copy, seen = {}, {}
  for i, entry in ipairs(entries) do
    local name = entry.name
    if type(name) ~= "string" or name == "" or #name > 100 or name:find("^/") or name:find("..", 1, true) or name:find("[%c\\]") then
      error("archive: bad entry name " .. tostring(name), 3)
    end
    if seen[name] then error("archive: duplicate entry " .. name, 3) end
    seen[name] = true
    copy[i] = entry
  end
  table.sort(copy, function(a, b) return a.name < b.name end)
  return copy
end

local function octal(value, width) return ("%0" .. (width - 1) .. "o\0"):format(value) end

--- The bytes of a ustar archive.
---@param entries tools.ArchiveEntry[]
---@return string
function M.tar(entries)
  local out = {}
  for _, entry in ipairs(sorted(entries)) do
    local fields = {
      entry.name .. ("\0"):rep(100 - #entry.name),
      octal(entry.mode or 420, 8), octal(0, 8), octal(0, 8), octal(#entry.data, 12), octal(M.MTIME, 12),
      "        ", "0", ("\0"):rep(100), "ustar\0", "00", ("\0"):rep(32), ("\0"):rep(32), octal(0, 8), octal(0, 8), ("\0"):rep(155),
    }
    local header = table.concat(fields)
    header = header .. ("\0"):rep(512 - #header)
    local sum = 0
    for i = 1, 512 do sum = sum + header:byte(i) end
    header = header:sub(1, 148) .. ("%06o\0 "):format(sum) .. header:sub(157)
    out[#out + 1] = header
    out[#out + 1] = entry.data
    out[#out + 1] = ("\0"):rep((512 - #entry.data % 512) % 512)
  end
  out[#out + 1] = ("\0"):rep(1024)
  return table.concat(out)
end

--- The bytes of a zip archive of stored (uncompressed) entries.
---@param entries tools.ArchiveEntry[]
---@return string
function M.zip(entries)
  local out, central, offset, count = {}, {}, 0, 0
  for _, entry in ipairs(sorted(entries)) do
    local crc, size = M.crc32(entry.data), #entry.data
    if size >= 0xFFFFFFFF then error("archive: " .. entry.name .. " is too large for a zip without zip64", 2) end
    -- version needed 10, flags 0, method 0 (stored), DOS time and date, crc, sizes, name length, extra length
    local common = string.pack("<I2I2I2I2I2I4I4I4I2I2", 10, 0, 0, DOS_TIME, DOS_DATE, crc, size, size, #entry.name, 0)
    local local_header = "PK\3\4" .. common .. entry.name
    out[#out + 1] = local_header
    out[#out + 1] = entry.data
    -- made by Unix (3), version 20; comment 0, disk 0, internal attributes 0, external attributes: (regular file | mode) << 16
    central[#central + 1] = "PK\1\2" .. string.pack("<I2I2I2I2I2I2I4I4I4I2I2I2I2I2I4I4", (3 << 8) | 20, 10, 0, 0, DOS_TIME, DOS_DATE,
      crc, size, size, #entry.name, 0, 0, 0, 0, (0x8000 | (entry.mode or 420)) << 16, offset) .. entry.name
    offset = offset + #local_header + size
    count = count + 1
  end
  local directory = table.concat(central)
  out[#out + 1] = directory
  out[#out + 1] = "PK\5\6" .. string.pack("<I2I2I2I2I4I4I2", 0, 0, count, count, #directory, offset, 0)
  return table.concat(out)
end

--- Reads the entries of a zip written by `M.zip` (stored entries): name, data, permission bits and whether the CRC
--- matched. Used by the tests.
---@param bytes string
---@return { name: string, data: string, mode: integer, crc_ok: boolean }[]? entries
---@return string? err
function M.read_zip(bytes)
  local eocd = #bytes - 21
  if eocd < 1 or bytes:sub(eocd, eocd + 3) ~= "PK\5\6" then return nil, "no end of central directory" end
  local count, _, directory = string.unpack("<I2I4I4", bytes, eocd + 10)
  local entries, position = {}, directory + 1
  for _ = 1, count do
    if bytes:sub(position, position + 3) ~= "PK\1\2" then return nil, "bad central directory entry" end
    local _, _, _, method, _, _, crc, size, _, name_length, extra_length, comment_length, _, _, attributes, offset =
      string.unpack("<I2I2I2I2I2I2I4I4I4I2I2I2I2I2I4I4", bytes, position + 4)
    if method ~= 0 then return nil, "compressed entry" end
    local name = bytes:sub(position + 46, position + 45 + name_length)
    local data_at = offset + 30 + #name + 1
    local data = bytes:sub(data_at, data_at + size - 1)
    entries[#entries + 1] = { name = name, data = data, mode = (attributes >> 16) & 0x1FF, crc_ok = M.crc32(data) == crc }
    position = position + 46 + name_length + extra_length + comment_length
  end
  return entries
end

--- Compresses the file `source` into `target` with `gzip -n` (no name, no time: the output depends only on the content and
--- on the gzip implementation). Returns true, or false and a message.
---@param source string
---@param target string
---@return boolean ok
---@return string? err
function M.gzip(source, target)
  local out, ok = util.capture(("gzip -n -9 -c < %s > %s"):format(util.quote(source), util.quote(target)))
  if not ok then return false, "gzip failed: " .. out end
  return true
end

return M
