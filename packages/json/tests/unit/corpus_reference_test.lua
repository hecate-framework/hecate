-- Runs tests/suites/corpus.lua against the reference backend.
local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
local suites = dofile(here .. "/../suites/load.lua")
return suites.load("corpus", "reference")
