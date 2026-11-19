local test = require("harness.test")
local doc = require("hecate.doc")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
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
  reactor.run(function()
    local ok, err = pcall(check_contract, self, fs, root)
    fs:remove_tree(root)
    self:assert_false(fs:exists(root), "the temporary directory is removed")
    if not ok then error(err, 0) end
  end)
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
  local ok, err = reactor.run(function()
    fs:write(root .. "/file", "x")
    local written, failure = pcall(function() fs:write(root .. "/file/child.txt", "y") end) -- a file is not a directory
    fs:remove_tree(root)
    return written, failure
  end)
  self:assert_false(ok)
  self:assert_true(core.is_instance_of(err, doc.BuildError))
end

local is_windows = package.config:sub(1, 1) == "\\"

local function temporary_root()
  local base = (os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP") or "/tmp"):gsub("\\", "/"):gsub("/+$", "")
  return ("%s/hecate-doc-link-%d-%d"):format(base, math.random(1, 1e9), os.time())
end

function T:test_remove_tree_unlinks_a_symlink_and_never_touches_its_target()
  if is_windows then return end
  local uv = require("luv")
  local root = temporary_root()
  local fs = doc.SystemFileSystem()
  reactor.run(function()
    local ok, err = pcall(function()
      fs:write(root .. "/target/keep.txt", "precious")
      assert(uv.fs_symlink(root .. "/target", root .. "/link"))
      self:assert_true(fs:is_link(root .. "/link"))
      self:assert_false(fs:is_link(root .. "/target"))
      self:assert_false(fs:is_link(root .. "/nowhere"))
      fs:remove_tree(root .. "/link/")
      self:assert_false(fs:exists(root .. "/link"), "the link is gone")
      self:assert_equal("precious", fs:read(root .. "/target/keep.txt"), "the target is intact")
    end)
    fs:remove_tree(root)
    if not ok then error(err, 0) end
  end)
end

function T:test_remove_tree_refuses_the_roots_however_they_are_written()
  local fs = doc.SystemFileSystem()
  for _, path in ipairs({ "", " ", "/", "//", ".", "./", "..", "a/..", "a/../..", "~", "C:/", "C:\\", "c:/.", "//server", "//server/share",
    "//server/share/", "/a/.." }) do
    local err = self:assert_error(function() fs:remove_tree(path) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), ("%q: %s"):format(path, tostring(err)))
  end
end

function T:test_the_memory_file_system_models_links()
  local fs = doc.MemoryFileSystem({ ["docs/en/index.md"] = "# Home\n", ["secret/key"] = "KEY" })
  fs:link("docs/en/key", "secret/key")
  fs:link("docs/en/outside", "secret")
  fs:link("docs/en/loop", "docs/en")
  fs:link("docs/en/dangling", "nowhere/file")
  self:assert_true(fs:is_link("docs/en/key"))
  self:assert_false(fs:is_link("docs/en/index.md"))
  self:assert_false(fs:is_link("docs/en"))
  self:assert_equal("KEY", fs:read("docs/en/key"), "a link is followed")
  self:assert_equal("KEY", fs:read("docs/en/outside/key"))
  local seen = {}
  for _, entry in ipairs(fs:list("docs/en") or {}) do seen[entry.name] = entry end
  self:assert_equal(true, seen.key.is_link)
  self:assert_equal(false, seen.key.is_directory)
  self:assert_equal(true, seen.outside.is_link)
  self:assert_equal(true, seen.outside.is_directory)
  self:assert_equal(true, seen.loop.is_directory)
  self:assert_equal(true, seen.dangling.is_link)
  self:assert_equal(false, seen["index.md"].is_link)
  self:assert_not_nil(fs:list("docs/en/loop/loop/loop"), "a link to a parent directory lists the parent again")
  self:assert_false(fs:exists("docs/en/dangling"), "stat follows a link")
  fs:write("docs/en/dangling", "WRITTEN") -- like a real file system: the target is created
  self:assert_equal("WRITTEN", fs.files["nowhere/file"])
  fs:remove_tree("docs/en/outside")
  self:assert_false(fs:is_link("docs/en/outside"))
  self:assert_equal("KEY", fs:read("secret/key"), "remove_tree unlinks and never follows")
  fs:link("a", "b")
  fs:link("b", "a")
  self:assert_nil(fs:read("a/x"), "a cycle of links reads nothing")
  self:assert_false(fs:exists("a/x"))
end

function T:test_system_file_system_reports_links_in_a_listing()
  if is_windows then return end
  local uv = require("luv")
  local root = temporary_root()
  local fs = doc.SystemFileSystem()
  reactor.run(function()
    local ok, err = pcall(function()
      fs:write(root .. "/target/file.txt", "precious")
      fs:write(root .. "/plain.txt", "p")
      assert(uv.fs_symlink(root .. "/target", root .. "/to_directory"))
      assert(uv.fs_symlink(root .. "/plain.txt", root .. "/to_file"))
      assert(uv.fs_symlink(root .. "/nowhere", root .. "/dangling"))
      assert(uv.fs_symlink(root, root .. "/target/up"))
      local seen = {}
      for _, entry in ipairs(fs:list(root) or {}) do seen[entry.name] = entry end
      self:assert_equal(true, seen.to_directory.is_link)
      self:assert_equal(true, seen.to_directory.is_directory)
      self:assert_equal(true, seen.to_file.is_link)
      self:assert_equal(false, seen.to_file.is_directory)
      self:assert_equal(true, seen.dangling.is_link)
      self:assert_equal(false, seen["plain.txt"].is_link)
      self:assert_equal(false, seen.target.is_link)
      self:assert_equal(true, fs:list(root .. "/target")[2].is_link, "a link to a parent directory is a link")
    end)
    fs:remove_tree(root)
    if not ok then error(err, 0) end
  end)
end

function T:test_system_file_system_never_writes_through_a_link()
  if is_windows then return end
  local uv = require("luv")
  local root = temporary_root()
  local fs = doc.SystemFileSystem()
  reactor.run(function()
    local ok, err = pcall(function()
      fs:write(root .. "/precious.txt", "precious")
      assert(uv.fs_symlink(root .. "/precious.txt", root .. "/to_file"))
      assert(uv.fs_symlink(root .. "/not-yet.txt", root .. "/dangling"))
      for _, name in ipairs({ "to_file", "dangling" }) do
        local failure = self:assert_error(function() fs:write(root .. "/" .. name, "overwritten") end)
        self:assert_true(core.is_instance_of(failure, doc.BuildError), tostring(failure))
        self:assert_not_nil(tostring(failure):find("symbolic link", 1, true), tostring(failure))
      end
      self:assert_equal("precious", fs:read(root .. "/precious.txt"))
      self:assert_false(fs:exists(root .. "/not-yet.txt"), "the target of a dangling link was not created")
    end)
    fs:remove_tree(root)
    if not ok then error(err, 0) end
  end)
end

-- Windows only: a junction (`mklink /J`) is a directory link that libuv may report differently from a symbolic link.
function T:test_system_file_system_sees_a_junction_as_a_link()
  if not is_windows then return end
  local root = temporary_root()
  local fs = doc.SystemFileSystem()
  reactor.run(function()
    local ok, err = pcall(function()
      fs:write(root .. "/target/file.txt", "precious")
      local native = root:gsub("/", "\\")
      assert(os.execute(('cmd /c mklink /J "%s\\junction" "%s\\target" > nul'):format(native, native)))
      local seen = {}
      for _, entry in ipairs(fs:list(root) or {}) do seen[entry.name] = entry end
      self:assert_equal(true, seen.junction.is_link, "the junction is a link")
      self:assert_true(fs:is_link(root .. "/junction"))
      self:assert_true(core.is_instance_of(self:assert_error(function() fs:write(root .. "/junction", "x") end), doc.BuildError))
      fs:remove_tree(root .. "/junction")
      self:assert_equal("precious", fs:read(root .. "/target/file.txt"), "removing the junction leaves the target")
    end)
    fs:remove_tree(root)
    if not ok then error(err, 0) end
  end)
end

return T
