-- The page behind an open menu or a full-screen diagram is locked on the root element only (owner report 2026-11-18):
-- `overflow: hidden` on <body> makes the body a scroll container, and the sticky header leaves the viewport. The
-- stylesheet is parsed rule by rule (nested `@media` blocks included), so that moving the class to `body`, or adding a
-- second rule, cannot go unseen whatever the spelling of the selector.
local test = require("harness.test")
local doc = require("hecate.doc")
local T = test.Case("ThemeScrollLockTest")

local function read(path)
  local file = assert(io.open(path, "rb"), path)
  local text = file:read("a")
  file:close()
  return text
end

local theme_dir = doc.theme.assets_directory()

--- The rules of a stylesheet, flattened: `{ selector = "html.a, body", body = "overflow: hidden;", context = "@media ..." }`.
--- A block whose prelude starts with `@` and holds rules (`@media`, `@supports`, `@layer`) is entered; `@font-face`
--- and `@keyframes` hold declarations or frames and are skipped as rules of no selector.
local function rules(css)
  css = css:gsub("/%*.-%*/", "")
  local out = {}
  local function parse(text, context)
    local position = 1
    while true do
      local open = text:find("{", position, true)
      if not open then return end
      local prelude = text:sub(position, open - 1):match("^%s*(.-)%s*$")
      local depth, close = 1, open + 1
      while depth > 0 and close <= #text do
        local char = text:sub(close, close)
        if char == "{" then depth = depth + 1 elseif char == "}" then depth = depth - 1 end
        close = close + 1
      end
      local inner = text:sub(open + 1, close - 2)
      if prelude:find("^@media") or prelude:find("^@supports") or prelude:find("^@layer") then
        parse(inner, prelude)
      elseif not prelude:find("^@") then
        out[#out + 1] = { selector = prelude, body = inner, context = context }
      end
      position = close
    end
  end
  parse(css, "")
  return out
end

--- Whether a declaration block locks overflow: `overflow`, `overflow-x` or `overflow-y` set to `hidden` or `clip`.
local function locks(body)
  for property, value in body:gmatch("([%w%-]+)%s*:%s*([^;}]+)") do
    if property == "overflow" or property == "overflow-x" or property == "overflow-y" then
      if value:find("hidden", 1, true) or value:find("clip", 1, true) then return true end
    end
  end
  return false
end

--- The problems of one selector (a single complex selector, no comma) for a rule that locks overflow.
local function selector_problem(selector)
  local last = selector:match("([^%s>+~]+)%s*$") or selector
  if last:find("^body[%.#:%[]") or last == "body" then return "targets body" end
  if selector:find("%f[%w_-]body%f[^%w_-]") then return "involves body" end
  for _, class in ipairs({ "scroll%-locked", "diagram%-fullscreen" }) do
    if selector:find("%." .. class .. "%f[^%w_-]") then
      -- The only accepted forms are on the root element: `html.<class>` or `:root.<class>`, nothing below it.
      if not (selector:find("^html%." .. class .. "$") or selector:find("^:root%." .. class .. "$")) then
        return "does not scope the lock class to the root element"
      end
    end
  end
  return nil
end

--- The problems of a stylesheet: every rule that locks overflow, selector by selector.
local function problems_of(css)
  local found = {}
  for _, rule in ipairs(rules(css)) do
    if locks(rule.body) then
      for raw in (rule.selector .. ","):gmatch("([^,]*),") do
        local selector = raw:match("^%s*(.-)%s*$")
        local problem = selector_problem(selector)
        if problem then found[#found + 1] = ("`%s` %s"):format(selector, problem) end
      end
    end
  end
  return found
end

local CSS = read(theme_dir .. "/theme.css")

function T:test_no_rule_that_locks_overflow_targets_the_body_or_an_unscoped_lock_class()
  local found = problems_of(CSS)
  self:assert_equal(0, #found, table.concat(found, "\n"))
end

function T:test_the_two_locks_exist_and_are_on_the_root_element()
  local seen = {}
  for _, rule in ipairs(rules(CSS)) do
    if locks(rule.body) then
      for raw in (rule.selector .. ","):gmatch("([^,]*),") do
        local selector = raw:match("^%s*(.-)%s*$")
        if selector == "html.scroll-locked" or selector == "html.diagram-fullscreen" then seen[selector] = (seen[selector] or 0) + 1 end
      end
    end
  end
  self:assert_equal(1, seen["html.scroll-locked"], "one rule locks the page for an open menu")
  self:assert_equal(1, seen["html.diagram-fullscreen"], "one rule locks the page for a full-screen diagram")
end

function T:test_the_checker_finds_what_it_is_there_to_find()
  local cases = {
    { "body { overflow: hidden; }", 1 },
    { "body.scroll-locked { overflow: hidden }", 1 },
    { "html.scroll-locked body { overflow:hidden; }", 1 },
    { ".scroll-locked { overflow: hidden; }", 1 },
    { ".diagram-fullscreen { overflow-y: hidden; }", 1 },
    { "div.scroll-locked { overflow: clip; }", 1 },
    { "@media (max-width: 959px) {\n  html.x, body { overflow: hidden; }\n}", 1 },
    { "@media (max-width: 959px) {\n  @supports (display: grid) {\n    body#top { overflow-x: hidden; }\n  }\n}", 1 },
    { "html.scroll-locked, body.scroll-locked { overflow: hidden; }", 1 },
    { ":root.scroll-locked { overflow: hidden; }", 0 },
    { "html.scroll-locked { overflow: hidden; }", 0 },
    { "@media (max-width: 959px) { html.diagram-fullscreen { overflow: hidden; } }", 0 },
    { "body { overflow: auto; }", 0 },
    { "body { overflow-y: scroll; margin: 0; }", 0 },
    { ".sidebar { overflow-y: auto; } .doc-body-wrap { overflow: hidden; }", 0 },
  }
  for _, case in ipairs(cases) do
    local found = problems_of(case[1])
    self:assert_equal(case[2], #found, ("%s -> %s"):format(case[1], table.concat(found, "; ")))
  end
  -- A comment does not hide a rule, and a commented-out rule is not one.
  self:assert_equal(1, #problems_of("/* html.scroll-locked */ body { overflow: hidden; }"))
  self:assert_equal(0, #problems_of("/* body { overflow: hidden; } */ html.scroll-locked { overflow: hidden; }"))
end

local function scripts()
  return { { name = "theme.js", text = read(theme_dir .. "/theme.js") }, { name = "mermaid-init.js", text = read(theme_dir .. "/mermaid-init.js") } }
end

function T:test_both_scripts_bind_root_to_the_document_element_once()
  for _, script in ipairs(scripts()) do
    local _, bindings = script.text:gsub("var%s+root%s*=%s*document%.documentElement%s*;", "")
    self:assert_equal(1, bindings, script.name .. ": `var root = document.documentElement;` once")
    -- And `root` is never assigned anything else (a second `var root`, or `root = document.body`).
    local _, declarations = script.text:gsub("[^%w_%.]var%s+root%s*[=;,]", "")
    self:assert_equal(1, declarations, script.name .. ": one declaration of root")
    local without_declaration = script.text:gsub("var%s+root%s*=%s*document%.documentElement%s*;", "")
    self:assert_nil(without_declaration:find("[^%w_%.]root%s*=[^=]"), script.name .. ": root is assigned only by its declaration")
  end
end

function T:test_the_lock_classes_are_toggled_on_root_and_never_on_the_body_or_the_element_of_a_diagram()
  local expected = { ["theme.js"] = "scroll-locked", ["mermaid-init.js"] = "diagram-fullscreen" }
  for _, script in ipairs(scripts()) do
    local class = expected[script.name]
    local count = 0
    for receiver, method in script.text:gmatch("([%w_%.%[%]]+)%.classList%.(%a+)%(%s*[\"']" .. class:gsub("%-", "%%-") .. "[\"']") do
      count = count + 1
      self:assert_equal("root", receiver, ("%s: `%s.classList.%s(\"%s\")` must be called on root"):format(script.name, receiver, method, class))
    end
    self:assert_true(count >= 1, script.name .. ": the class " .. class .. " is set on root")
    -- No other way to reach the class: a string key on the class list of the body, `className`, `setAttribute("class")`.
    self:assert_nil(script.text:find("document%.body%.classList", 1), script.name .. ": nothing is set on the body")
    self:assert_nil(script.text:find("document%.body%.className"), script.name)
    self:assert_nil(script.text:find("document%.body%.style"), script.name .. ": no inline overflow on the body")
    self:assert_nil(script.text:find("%.style%.overflow"), script.name .. ": the lock is a class, not an inline style")
  end
  -- Each script locks with its own class only: the classes are not mixed.
  local text = scripts()
  self:assert_nil(text[1].text:find("diagram%-fullscreen"))
  self:assert_nil(text[2].text:find("scroll%-locked"))
end

return T
