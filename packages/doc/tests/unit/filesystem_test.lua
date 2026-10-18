local test = require("harness.test")
local doc = require("hecate.doc")
local core = require("hecate.core")
local T = test.Case("FileSystemTest")

local function names(entries)
  local out = {}
  for _, entry in ipairs(entries or {}) do out[#out + 1] = entry.name .. (entry.is_directory and "/" or "") end
  return table.concat(out, ",")
end

--- The contract every implementation must satisfy.
local function check_contract(self, fs, root)
  self:assert_nil(fs:read(root .. "/missing.txt"))
  self:assert_nil(fs:list(root .. "/nowhere"))
  self:assert_false(fs:exists(root .. "/nowhere"))
  fs:write(root .. "/b.txt", "bee")
  fs:write(root .. "/a/deep/c.bin", "\0\1\255binary\r\n")
  fs:write(root .. "/a/z.txt", "")
  fs:write(root .. "/.hidden", "h")
  self:assert_equal("bee", fs:read(root .. "/b.txt"))
  self:assert_equal("\0\1\255binary\r\n", fs:read(root .. "/a/deep/c.bin"), "binary content survives")
  self:assert_equal("", fs:read(root .. "/a/z.txt"))
  self:assert_equal(".hidden,a/,b.txt", names(fs:list(root)))
  self:assert_equal("deep/,z.txt", names(fs:list(root .. "/a")))
  self:assert_true(fs:exists(root .. "/b.txt"))
  self:assert_true(fs:exists(root .. "/a/deep"))
  fs:write(root .. "/b.txt", "bee2")
  self:assert_equal("bee2", fs:read(root .. "/b.txt"), "write replaces")
  fs:remove_tree(root .. "/a")
  self:assert_false(fs:exists(root .. "/a"))
  self:assert_nil(fs:read(root .. "/a/deep/c.bin"))
  self:assert_equal(".hidden,b.txt", names(fs:list(root)))
end

function T:test_memory_file_system_satisfies_the_contract()
  local fs = doc.MemoryFileSystem()
  self:assert_true(core.implements(fs, doc.FileSystem))
  check_contract(self, fs, "root")
end

function T:test_memory_file_system_normalises_paths_and_rejects_non_strings()
  local fs = doc.MemoryFileSystem({ ["./a//b/../c.txt"] = "x" })
  self:assert_equal("x", fs:read("a/c.txt"))
  self:assert_equal("x", fs:read("a/./c.txt"))
  ---@diagnostic disable-next-line: param-type-mismatch  -- the misuse under test
  self:assert_true(core.is_instance_of(self:assert_error(function() fs:write("a", 1) end), core.ArgumentError))
  fs:write("t/x", "1")
  self:assert_equal("t/", names(fs:list("")):match("t/"))
end

function T:test_system_file_system_satisfies_the_contract()
  local base = os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
  base = base:gsub("\\", "/"):gsub("/+$", "")
  math.randomseed(os.time() + math.floor(os.clock() * 1e6))
  local root = ("%s/hecate-doc-test-%d-it's here"):format(base, math.random(1, 1e9))
  local fs = doc.SystemFileSystem()
  self:assert_true(core.implements(fs, doc.FileSystem))
  local ok, err = pcall(check_contract, self, fs, root)
  fs:remove_tree(root)
  self:assert_false(fs:exists(root), "the temporary directory is removed")
  if not ok then error(err, 0) end
end

function T:test_system_file_system_refuses_to_remove_a_root()
  local fs = doc.SystemFileSystem()
  for _, path in ipairs({ "", "/", ".", ".." }) do
    self:assert_true(core.is_instance_of(self:assert_error(function() fs:remove_tree(path) end), core.ArgumentError), path)
  end
end

function T:test_system_file_system_reports_unwritable_paths_as_build_errors()
  local base = (os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP") or "/tmp"):gsub("\\", "/"):gsub("/+$", "")
  local root = ("%s/hecate-doc-test-file-%d"):format(base, math.random(1, 1e9))
  local fs = doc.SystemFileSystem()
  fs:write(root .. "/file", "x")
  local ok, err = pcall(function() fs:write(root .. "/file/child.txt", "y") end) -- a file is not a directory
  fs:remove_tree(root)
  self:assert_false(ok)
  self:assert_true(core.is_instance_of(err, doc.BuildError))
end

return T
