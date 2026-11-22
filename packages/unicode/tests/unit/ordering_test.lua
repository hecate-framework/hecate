-- The Canonical Ordering Algorithm (Unicode Standard 3.11, D108 and D109) and its two code paths: a run of at most
-- `algorithm.INSERTION_LIMIT` non-starters is ordered by insertion, a longer one by a sort of integer keys, so that a
-- hostile string of thousands of marks costs n log n and not n squared.
local test = require("harness.test")
local unicode = require("hecate.unicode")
local algorithm = require("hecate.unicode.internal.algorithm")
local tables = require("hecate.unicode.internal.tables")
local T = test.Case("UnicodeOrderingTest")

local DEFAULT_LIMIT = algorithm.INSERTION_LIMIT

function T:tear_down() algorithm.INSERTION_LIMIT = DEFAULT_LIMIT end

--- Marks that have no decomposition (so NFD leaves them as they are), grouped by combining class, each group sorted.
local function pool()
  local loaded = tables.get()
  local by_class, classes = {}, {}
  for codepoint, class in pairs(loaded.combining_class) do
    if codepoint < 0x370 and not loaded.decomposition[codepoint] then
      if not by_class[class] then
        by_class[class] = {}
        classes[#classes + 1] = class
      end
      table.insert(by_class[class], codepoint)
    end
  end
  table.sort(classes)
  local all = {}
  for _, class in ipairs(classes) do
    table.sort(by_class[class])
    for _, codepoint in ipairs(by_class[class]) do all[#all + 1] = codepoint end
  end
  return all
end

--- The stable sort of the definition, written as a sort on (class, original position).
local function reference(marks)
  local classes = tables.get().combining_class
  local indexed = {}
  for index, codepoint in ipairs(marks) do indexed[index] = { codepoint = codepoint, index = index, class = classes[codepoint] } end
  table.sort(indexed, function(a, b)
    if a.class ~= b.class then return a.class < b.class end
    return a.index < b.index
  end)
  local out = {}
  for index, entry in ipairs(indexed) do out[index] = utf8.char(entry.codepoint) end
  return table.concat(out)
end

local function encode(marks)
  local out = {}
  for index, codepoint in ipairs(marks) do out[index] = utf8.char(codepoint) end
  return table.concat(out)
end

function T:test_the_default_limit_is_the_documented_one()
  self:assert_equal(24, algorithm.INSERTION_LIMIT)
end

-- Runs of 1 to 80 marks (distinct members, several of one class: only a stable sort keeps their order), separated by
-- starters, in NFD (against the definition) and NFC (the paths against each other), with the insertion path always, the sort path always and the default limit.
function T:test_both_paths_give_the_stable_sort_of_the_definition_on_random_runs()
  math.randomseed(20261119)
  local all = pool()
  self:assert_true(#all >= 80, "the pool holds enough distinct marks for a run of 80")
  for round = 1, 400 do
    local text, expected = {}, {}
    for _ = 1, math.random(1, 3) do
      local shuffled = table.move(all, 1, #all, 1, {})
      for index = #shuffled, 2, -1 do
        local other = math.random(1, index)
        shuffled[index], shuffled[other] = shuffled[other], shuffled[index]
      end
      local length = math.random(1, 80)
      local marks = table.move(shuffled, 1, length, 1, {})
      text[#text + 1] = "b" .. encode(marks)
      expected[#expected + 1] = "b" .. reference(marks)
    end
    local input, wanted = table.concat(text), table.concat(expected)
    local results, composed = {}, {}
    for _, limit in ipairs({ 0, DEFAULT_LIMIT, 1000000000 }) do
      algorithm.INSERTION_LIMIT = limit
      results[#results + 1] = unicode.nfd(input)
      composed[#composed + 1] = unicode.nfc(input)
      self:assert_equal(wanted, results[#results], ("round %d, limit %d"):format(round, limit))
    end
    self:assert_equal(results[1], results[2])
    self:assert_equal(results[2], results[3])
    -- NFC composes some of the marks with the letter (b with dot above): the three paths agree on the result as well.
    self:assert_equal(composed[1], composed[2])
    self:assert_equal(composed[2], composed[3])
  end
end

function T:test_a_run_exactly_at_the_limit_and_one_above_it_agree()
  algorithm.INSERTION_LIMIT = 24 -- the boundary of the documented limit, whatever the default is
  local all = pool()
  for _, length in ipairs({ 23, 24, 25 }) do
    local marks = {}
    for index = 1, length do marks[index] = all[#all - index + 1] end -- the highest classes first: worst order
    local text = "x" .. encode(marks)
    self:assert_equal("x" .. reference(marks), unicode.nfd(text), "length " .. length)
  end
end

--- `tables` whose combining class lookups are counted; a lookup beyond `budget` raises, so that a quadratic path fails
--- at once instead of running for a minute.
local function counting(budget)
  local real = tables.get()
  local counter = { lookups = 0 }
  local classes = setmetatable({}, { __index = function(_, codepoint)
    counter.lookups = counter.lookups + 1
    if counter.lookups > budget then error("more than " .. budget .. " class lookups: the ordering is not n log n", 0) end
    return real.combining_class[codepoint]
  end })
  return { combining_class = classes, decomposition = real.decomposition, composition = real.composition }, counter
end

local function worst_run(marks)
  -- 230 then 220, again and again: every mark of class 220 has to cross all the marks of class 230 before it.
  return "a" .. ("\u{301}\u{323}"):rep(marks // 2)
end

function T:test_a_long_run_of_marks_costs_a_number_of_operations_that_grows_linearly_with_its_length()
  local counts = {}
  for _, marks in ipairs({ 2000, 4000, 8000 }) do
    local proxy, counter = counting(12 * marks)
    local result = algorithm.normalise(worst_run(marks), false, proxy)
    self:assert_equal("a" .. ("\u{323}"):rep(marks // 2) .. ("\u{301}"):rep(marks // 2), result)
    counts[#counts + 1] = counter.lookups
  end
  -- Doubling the input at most doubles the work (a margin of 25% for the runs and the keys), where an insertion sort
  -- would multiply it by four.
  self:assert_true(counts[2] <= counts[1] * 2.5, ("%d lookups for 4000, %d for 2000"):format(counts[2], counts[1]))
  self:assert_true(counts[3] <= counts[2] * 2.5, ("%d lookups for 8000, %d for 4000"):format(counts[3], counts[2]))
end

function T:test_the_same_holds_for_composition_and_for_one_long_run_of_one_class()
  local proxy = counting(12 * 8000)
  algorithm.normalise(worst_run(8000), true, proxy)
  local same_class = "a" .. ("\u{301}\u{302}\u{303}\u{304}"):rep(2000)
  local proxy_two, counter = counting(12 * 8000)
  self:assert_equal(algorithm.normalise(same_class, false, proxy_two), same_class, "equal classes keep their order")
  self:assert_true(counter.lookups <= 12 * 8000)
end

function T:test_the_instrument_detects_a_quadratic_path()
  -- Guards the guard: with every run sorted by insertion the budget is exceeded, so the test above can fail.
  algorithm.INSERTION_LIMIT = 1000000000
  local proxy = counting(12 * 4000)
  local err = self:assert_error(function() algorithm.normalise(worst_run(4000), false, proxy) end)
  self:assert_true(tostring(err):find("not n log n", 1, true) ~= nil, tostring(err))
end

return T
