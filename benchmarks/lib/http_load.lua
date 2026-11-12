-- HTTP/1.1 load generator shared by the `plaintext` and `kernel-json` scenarios. Each connection stays open (keep-alive)
-- and sends, at a constant arrival rate, a batch of `pipeline` GET requests written at once (1: no pipelining);
-- latency is measured from the instant a batch was due, not from the instant it was sent, so a slow server cannot
-- hide its queueing (coordinated omission). A response with a status other than 200, or one this generator cannot
-- frame (no `Content-Length`), counts in `bad responses` and closes that connection; a batch still unanswered 10 s
-- after the end of the run counts in `errors`. Throughput counts every response completed after the warm-up, divided
-- by the time from the end of the warm-up to the last response (or the duration, when longer).
-- Prints measurement lines (`label value unit`): throughput, errors, bad responses, p50/p90/p99/p99.9 and max latency.
global <const> io, arg, print, require, tonumber, ipairs, pcall, table, os, dofile, math, error

---@class benchmarks.HttpLoadDefaults
---@field path string  request target
---@field connections? integer
---@field rate? number  total requests per second
---@field pipeline? integer  requests written at once per connection

---@param defaults benchmarks.HttpLoadDefaults
return function(defaults)
  local reactor = require("hecate.reactor")
  local net = require("hecate.net")
  local stats = dofile("benchmarks/lib/stats.lua")

  local options = { host = "127.0.0.1", port = nil, connections = defaults.connections or 100,
    rate = defaults.rate or 1000, duration = 10, warmup = 2, pipeline = defaults.pipeline or 1, path = defaults.path }
  for _, a in ipairs(arg) do
    local key, value = a:match("^%-%-(%a+)=(.*)$")
    if key == "control" then key = nil end -- a control port is never given to an HTTP scenario
    if not key or options[key] == nil and key ~= "port" then
      io.stderr:write(("unknown argument '%s'\n"):format(a))
      os.exit(2)
    end
    if key == "host" or key == "path" then options[key] = value
    else options[key] = tonumber(value) or (io.stderr:write(("--%s needs a number\n"):format(key)) and os.exit(2)) end
  end
  if not options.port then
    io.stderr:write("--port is required\n")
    os.exit(2)
  end
  local pipeline = math.max(1, math.tointeger(options.pipeline) or 1)
  local request = ("GET %s HTTP/1.1\r\nHost: %s:%d\r\nAccept: */*\r\n\r\n"):format(options.path, options.host,
    options.port)
  local batch = request:rep(pipeline)
  local ANSWER_MARGIN <const> = 10 -- seconds a batch may still take after the end of the run
  local interval = options.connections * pipeline / options.rate -- seconds between two batches of one connection

  --- Reads one response; raises when it is not a 200 with a `Content-Length`.
  ---@param reader hecate.net.BufferedReader
  local function read_response(reader)
    local status_line = reader:read_line(8192)
    if status_line == nil then error("closed", 0) end
    local ok = status_line:match("^HTTP/1%.1 200 ") ~= nil
    local length
    while true do
      local line = reader:read_line(8192)
      if line == nil then error("closed", 0) end
      if line == "" then break end
      local name, value = line:match("^([^:]+):%s*(.-)%s*$")
      if name and name:lower() == "content-length" then length = tonumber(value) end
    end
    if not length then error("bad", 0) end
    if length > 0 then reader:read_exact(length, 1048576) end
    if not ok then error("bad", 0) end
  end

  local function run()
    local start, warm_until, stop -- set once every connection is open, so that connecting is not measured
    local latencies, errors, bad, completed, pending = {}, 0, 0, 0, options.connections
    local last_done = 0 -- instant of the last counted completion, so that a saturated server shows in the throughput

    local function client(index)
      local ok, connection = pcall(net.connect, options.host, options.port, { nodelay = true })
      pending = pending - 1
      if not ok then errors = errors + 1 return end
      local peer <close> = connection
      local reader = peer:reader()
      while not start do reactor.sleep(0.01) end
      -- connections are staggered over one interval so that arrivals are spread, not bursty
      local due = start + interval * (index - 1) / options.connections
      while due < stop do
        local wait = due - reactor.now()
        if wait > 0 then reactor.sleep(wait) end
        -- a server that stops answering must not hang the run: a batch has until the end plus a margin
        local sent, problem = pcall(reactor.deadline, math.max(0, stop - reactor.now()) + ANSWER_MARGIN, function()
          peer:write(batch)
          for _ = 1, pipeline do
            read_response(reader)
            local now = reactor.now()
            -- latency for the requests due after the warm-up; throughput for every response that completes in the
            -- measured window, so that requests queued during a saturated warm-up are not served uncounted
            if due >= warm_until then latencies[#latencies + 1] = now - due end
            if now >= warm_until then
              completed = completed + 1
              last_done = now
            end
          end
        end)
        if not sent then
          if problem == "bad" then bad = bad + 1 else errors = errors + 1 end
          return
        end
        due = due + interval
      end
    end

    local scope = {}
    for i = 1, options.connections do scope[i] = reactor.fork(client, i) end
    while pending > 0 do reactor.sleep(0.01) end
    start = reactor.now() + 0.5
    warm_until = start + options.warmup
    stop = warm_until + options.duration
    reactor.join(table.unpack(scope))
    return latencies, errors, bad, completed, math.max(options.duration, last_done - warm_until)
  end

  local latencies, errors, bad, completed, elapsed = reactor.run(run)
  local function microseconds(seconds) return seconds * 1e6 end
  print(("throughput %.0f requests/s"):format(completed / elapsed))
  print(("errors %d connections"):format(errors))
  print(("bad responses %d connections"):format(bad))
  if #latencies > 0 then
    table.sort(latencies)
    for _, p in ipairs({ { "p50", 50 }, { "p90", 90 }, { "p99", 99 }, { "p99.9", 99.9 } }) do
      print(("latency %s %.1f us"):format(p[1], microseconds(stats.percentile(latencies, p[2]))))
    end
    print(("latency max %.1f us"):format(microseconds(latencies[#latencies])))
  end
end
