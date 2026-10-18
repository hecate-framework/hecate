-- The examples included in the reference pages are tested files: each one runs without error
-- and prints what its last line (`-- Prints: ...`) says. Reference generation reads them from
-- `examples/<symbol>.lua` (coding-standards.md, "Annotations for the reference").
local test = require("harness.test")
local T = test.Case("ExamplesTest")

local here = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
local directory = here:match("^(.*)/tests/unit/") .. "/examples"
local NAMES = { "hecate.net.connect", "hecate.net.bind_udp", "hecate.net.connect_tls", "hecate.net.tls.accept" }
local NEEDS_TLS = { ["hecate.net.connect_tls"] = true, ["hecate.net.tls.accept"] = true }

function T:test_every_example_runs_and_prints_what_it_says()
  local tls_available = require("hecate.net").tls.available()
  for _, name in ipairs(NAMES) do
    -- The TLS examples need the native module: skipped, visibly, unless HECATE_REQUIRE_TLS=1 (then a failure).
    if NEEDS_TLS[name] and not tls_available and os.getenv("HECATE_REQUIRE_TLS") ~= "1" then
      print("SKIP " .. name .. ": the native TLS module is not built")
      goto continue
    end
    local path = ("%s/%s.lua"):format(directory, name)
    local file = assert(io.open(path, "rb"))
    local source = file:read("a")
    file:close()
    local expected = source:match("%-%- Prints: ([^\n]*)%s*$")
    self:assert_not_nil(expected, path .. " has no `-- Prints:` line")
    local lines = {}
    local environment = setmetatable({ print = function(...)
      local parts = table.pack(...)
      for i = 1, parts.n do parts[i] = tostring(parts[i]) end
      lines[#lines + 1] = table.concat(parts, "\t")
    end }, { __index = _G })
    local chunk = assert(load(source, "@" .. path, "t", environment))
    chunk()
    self:assert_equal(expected, table.concat(lines, "\n"), path)
    ::continue::
  end
end

return T
