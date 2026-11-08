-- A small deterministic pseudo-random generator for the seeded tests (xorshift64, Marsaglia 2003). No clock is read:
-- the seed is fixed in the source, overridden by the environment variable `HECATE_TEST_SEED` (an integer), and printed
-- with every failure raised through `run`, so that a failing run is reproduced with the same seed.
local M = {}

local DEFAULT_SEED = 0x2545F4914F6CDD1D

--- The seed of this run: `HECATE_TEST_SEED` when it is an integer, else `default` (a number fixed in the test).
---@param default? integer
---@return integer
function M.seed(default)
  local from_environment = math.tointeger(tonumber(os.getenv("HECATE_TEST_SEED") or ""))
  return from_environment or default or DEFAULT_SEED
end

---@class tests.Prng
---@field seed integer
---@field next fun(): integer         the next 64-bit value
---@field int fun(low: integer, high: integer): integer  uniform in [low, high]
---@field chance fun(numerator: integer, denominator: integer): boolean
---@field pick fun(list: any[]): any

--- A generator for `seed`.
---@param seed integer
---@return tests.Prng
function M.new(seed)
  local state = seed ~= 0 and seed or DEFAULT_SEED
  local self = { seed = seed }
  function self.next()
    state = state ~ (state << 13)
    state = state ~ (state >> 7)
    state = state ~ (state << 17)
    return state
  end
  function self.int(low, high)
    return low + (self.next() >> 1) % (high - low + 1)
  end
  function self.chance(numerator, denominator) return self.int(1, denominator) <= numerator end
  function self.pick(list) return list[self.int(1, #list)] end
  return self
end

--- Runs `fn(rng)` with a generator seeded by `seed(default)`; a failure carries the seed in its message.
---@param default? integer
---@param fn fun(rng: tests.Prng)
function M.run(default, fn)
  local seed = M.seed(default)
  local ok, err = pcall(fn, M.new(seed))
  if ok then return end
  local note = ("\n[seed %d: rerun with HECATE_TEST_SEED=%d]"):format(seed, seed)
  if type(err) == "table" and err.harness_failure then
    err.harness_failure = err.harness_failure .. note
    error(err, 0)
  end
  error(tostring(err) .. note, 0)
end

return M
