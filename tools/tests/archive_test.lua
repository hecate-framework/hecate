local test = require("harness.test")
local archive = require("lib.archive")
local util = require("lib.util")
local T = test.Case("ArchiveTest")

local ENTRIES = {
  { name = "hecate", data = ("binary\0bytes"):rep(100), mode = 493 },
  { name = "lua55.dll", data = "dll", mode = 420 },
}

local function write(path, data)
  local f = assert(io.open(path, "wb"))
  f:write(data)
  f:close()
end

function T:set_up()
  self.dir = assert(util.make_temp_dir(".hecate/tmp", "archive-test"))
end

function T:tear_down() util.remove_tree(self.dir) end

function T:test_crc32_matches_the_check_value()
  self:assert_equal(0xCBF43926, archive.crc32("123456789"))
  self:assert_equal(0, archive.crc32(""))
end

function T:test_the_tar_is_the_same_whatever_the_order_of_the_entries()
  local reversed = { ENTRIES[2], ENTRIES[1] }
  self:assert_true(archive.tar(ENTRIES) == archive.tar(reversed))
  self:assert_true(archive.zip(ENTRIES) == archive.zip(reversed))
end

function T:test_the_tar_has_whole_blocks_and_fixed_metadata()
  local bytes = archive.tar(ENTRIES)
  self:assert_equal(0, #bytes % 512)
  self:assert_equal("hecate", bytes:sub(1, 6))
  self:assert_equal("ustar\0", bytes:sub(258, 263))
  self:assert_equal(("%011o"):format(archive.MTIME), bytes:sub(137, 147))
  self:assert_equal("0000755\0", bytes:sub(101, 108))
  self:assert_equal("0000000\0", bytes:sub(109, 116)) -- owner 0
end

function T:test_the_platform_tar_reads_the_tar()
  local _, have = util.capture(util.tar_command() .. " --version")
  if not have then return end
  local path = self.dir .. "/a.tar"
  write(path, archive.tar(ENTRIES))
  local out, ok = util.capture(("%s -tvf %s 2>&1"):format(util.tar_command(), util.quote(path)))
  self:assert_true(ok, out)
  self:assert_true(out:find("hecate", 1, true) ~= nil, out)
  self:assert_true(out:find("lua55.dll", 1, true) ~= nil, out)
  local target = self.dir .. "/x"
  util.mkdir(target)
  out, ok = util.capture(("%s -xf %s -C %s 2>&1"):format(util.tar_command(), util.quote(path), util.quote(target)))
  self:assert_true(ok, out)
  local f = assert(io.open(target .. "/lua55.dll", "rb"))
  self:assert_equal("dll", f:read("a"))
  f:close()
end

function T:test_the_zip_reads_back_with_its_checksums()
  local entries = assert(archive.read_zip(archive.zip(ENTRIES)))
  self:assert_equal(2, #entries)
  self:assert_equal("hecate", entries[1].name)
  self:assert_equal(ENTRIES[1].data, entries[1].data)
  self:assert_equal(493, entries[1].mode)
  self:assert_true(entries[1].crc_ok and entries[2].crc_ok)
end

function T:test_the_platform_tar_unpacks_the_zip()
  local _, have = util.capture(util.tar_command() .. " --version")
  if not have then return end
  local path = self.dir .. "/a.zip"
  write(path, archive.zip(ENTRIES))
  local target = self.dir .. "/x"
  util.mkdir(target)
  local _, ok = util.capture(("%s -xf %s -C %s 2>&1"):format(util.tar_command(), util.quote(path), util.quote(target)))
  if not ok then return end -- a tar that does not read zip (GNU tar on Linux); the Windows tar does, and CI runs it there
  local f = assert(io.open(target .. "/hecate", "rb"))
  self:assert_equal(ENTRIES[1].data, f:read("a"))
  f:close()
end

function T:test_gzip_is_deterministic()
  local _, have = util.capture("gzip --version")
  if not have then return end
  local source = self.dir .. "/a.tar"
  write(source, archive.tar(ENTRIES))
  self:assert_true(archive.gzip(source, self.dir .. "/1.gz"))
  self:assert_true(archive.gzip(source, self.dir .. "/2.gz"))
  local a, b = io.open(self.dir .. "/1.gz", "rb"), io.open(self.dir .. "/2.gz", "rb")
  self:assert_equal(a:read("a"), b:read("a"))
  a:close()
  b:close()
end

function T:test_bad_and_duplicate_names_are_refused()
  self:assert_error(function() archive.tar({ { name = "../x", data = "" } }) end, "bad entry name")
  self:assert_error(function() archive.tar({ { name = "/x", data = "" } }) end, "bad entry name")
  self:assert_error(function() archive.zip({ { name = ("a"):rep(101), data = "" } }) end, "bad entry name")
  self:assert_error(function() archive.zip({ { name = "a", data = "" }, { name = "a", data = "" } }) end, "duplicate")
end

return T
