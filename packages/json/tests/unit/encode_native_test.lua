-- Runs tests/suites/encode.lua against the native backend.
local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local suites = dofile(here .. "/../suites/load.lua")
return suites.load("encode", "native")
