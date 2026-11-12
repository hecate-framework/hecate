-- kernel-json load: `GET /json` over keep-alive connections at a constant arrival rate (benchmarks/lib/http_load.lua).
-- Usage: lua benchmarks/scenarios/kernel-json/load.lua --port=N [--host=ADDR] [--connections=N]
--          [--rate=REQUESTS_PER_SECOND] [--duration=SECONDS] [--warmup=SECONDS] [--pipeline=N] [--path=TARGET]
global <const> dofile
dofile("benchmarks/lib/setup.lua")({ "core", "reactor", "net" })
dofile("benchmarks/lib/http_load.lua")({ path = "/json" })
