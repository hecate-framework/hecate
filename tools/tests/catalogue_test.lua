local test = require("harness.test")
local catalogue = require("lib.catalogue")
local T = test.Case("CatalogueTest")

local README = "# `hecate-x`\n\n> Does things.\n\n| | |\n|---|---|\n| Rock | `hecate-x` |\n| Layer | 1 — Runtime |\n| Roadmap phase | 2 |\n| Status | specified — no code yet |\n"

function T:test_parse()
  local m = catalogue.parse_readme(README)
  self:assert_equal("Does things.", m.summary)
  self:assert_equal("specified", m.status)
  self:assert_equal("hecate-x", m.rock)
end
function T:test_render_sorts_by_phase()
  local a = catalogue.parse_readme(README)
  local b = catalogue.parse_readme((README:gsub("phase | 2", "phase | 1")))
  local out = catalogue.render({ { name = "a", meta = a }, { name = "b", meta = b } })
  self:assert_true(out:find("`b`", 1, true) < out:find("`a`", 1, true))
end
function T:test_replace_table()
  local out = catalogue.replace_table("intro\n\n| a |\n|---|\n| b |\n\nafter\n", "| new |")
  self:assert_equal("intro\n\n| new |\n\nafter\n", out)
end
return T
