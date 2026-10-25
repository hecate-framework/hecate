-- Helpers of the `fuzz` task: argument parsing, target lookup and the cargo-fuzz command line.
local M = {}

--- Parses `<target> [--seconds n]`; nil when the arguments are invalid.
---@param args string[]
---@return {target: string, seconds: integer}?
function M.parse(args)
  local options = { seconds = 60 }
  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--seconds" then
      local n = math.tointeger(tonumber(args[i + 1]))
      if not n or n < 1 then return nil end
      options.seconds = n
      i = i + 1
    elseif not options.target and a:sub(1, 2) ~= "--" then
      options.target = a
    else
      return nil
    end
    i = i + 1
  end
  if not options.target then return nil end
  return options
end

--- Finds a target by name.
---@param targets {package: string, name: string}[]
---@param name string
---@return {package: string, name: string}?
function M.find(targets, name)
  for _, t in ipairs(targets) do
    if t.name == name then return t end
  end
  return nil
end

--- Command line that fuzzes one target for a bounded time (coding-standards.md; packages/net/native/fuzz/README.md).
---@param crate string directory of the Rust crate
---@param name string
---@param seconds integer
---@return string
function M.command(crate, name, seconds)
  return ("cd %s && cargo +nightly fuzz run %s -- -max_total_time=%d"):format(crate, name, seconds)
end

return M
