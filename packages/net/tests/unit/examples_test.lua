-- The examples included in the reference pages are tested files: each one runs without error, and what a line
-- prints is written in a `-- Prints:` block directly under that line (the shared runner
-- `tools/harness/examples.lua`). Reference generation reads them from
-- `examples/<symbol>.lua` (coding-standards.md, "Annotations for the reference").
local test = require("harness.test")
local examples = require("harness.examples")
local T = test.Case("ExamplesTest")

local here = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
local directory = here:match("^(.*)/tests/unit/") .. "/examples"
local NAMES = {
  "hecate.net.connect", "hecate.net.listen", "hecate.net.bind_udp", "hecate.net.resolve", "hecate.net.listen_pipe",
  "hecate.net.TcpStream.read", "hecate.net.TcpStream.shutdown",
  "hecate.net.connect_tls", "hecate.net.tls.accept", "hecate.net.tls.server_config", "hecate.net.TlsError",
}
local NEEDS_TLS = {
  ["hecate.net.connect_tls"] = true, ["hecate.net.tls.accept"] = true, ["hecate.net.tls.server_config"] = true,
  ["hecate.net.TlsError"] = true,
}

function T:test_every_example_runs_and_prints_what_it_says()
  local tls_available = require("hecate.net").tls.available()
  local problems = {}
  for _, name in ipairs(NAMES) do
    -- The TLS examples need the native module: skipped, visibly, unless HECATE_REQUIRE_TLS=1 (then a failure).
    if NEEDS_TLS[name] and not tls_available and os.getenv("HECATE_REQUIRE_TLS") ~= "1" then
      print("SKIP " .. name .. ": the native TLS module is not built")
      goto continue
    end
    local problem = examples.run(("%s/%s.lua"):format(directory, name))
    problems[#problems + 1] = problem
    ::continue::
  end
  if #problems > 0 then self:fail(table.concat(problems, "\n")) end
end

return T
