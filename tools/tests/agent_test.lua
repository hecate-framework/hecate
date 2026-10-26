local test = require("harness.test")
local util = require("lib.util")
local agent = require("lib.agent")
local T = test.Case("AgentTest")

local function read(path)
  local f = assert(io.open(path, "rb"))
  local text = f:read("a")
  f:close()
  return text
end

function T:test_about_lowers_ordinary_words_and_keeps_names()
  self:assert_equal("the application: x", agent.about("The application: x"))
  self:assert_equal("fast, correct codec", agent.about("Fast, correct codec"))
  self:assert_equal("HTTP/1.1 server", agent.about("HTTP/1.1 server"))
  self:assert_equal("MySQL and MariaDB driver", agent.about("MySQL and MariaDB driver"))
  self:assert_equal("Redis client", agent.about("Redis client"))
end

function T:test_allowed_lists_packages_or_the_standard_library()
  self:assert_equal("Lua standard library only.", agent.allowed({}))
  self:assert_equal("`hecate.core`, `hecate.net`.", agent.allowed({ "core", "net" }))
end

--- Every existing agent is what the template renders from its own scope, document, dependencies and standards: the
--- scaffold of `new-package` and the agents of the repository cannot drift apart.
function T:test_the_template_reproduces_every_package_agent()
  local checked = 0
  for _, file in ipairs(util.list_dir(".claude/agents")) do
    local name = file:match("^pkg%-(.+)%.md$")
    if name then
      local text = read(".claude/agents/" .. file)
      local rendered = agent.render({
        name = name,
        module = text:match("maintainer of `([^`]+)`"),
        scope = text:match("\nScope: ([^\n]+)"),
        doc = text:match("\n2%. Read `([^`]+)`"),
        allowed = text:match("\n%- Allowed dependencies: ([^\n]+)"),
        standards = text:match("\n%- Relevant standards: (.-)%. Cite section numbers"),
      })
      self:assert_equal(text, rendered, "pkg-" .. name .. " differs from the template")
      checked = checked + 1
    end
  end
  self:assert_true(checked >= 28, "found " .. checked .. " package agents")
end

local function remove_tree(path)
  if util.is_windows() then os.execute(('rmdir /s /q "%s" >nul 2>&1'):format(path:gsub("/", "\\")))
  else os.execute("rm -rf " .. util.quote(path)) end
end

--- `new-package` on a scratch repository writes the template agent.
function T:test_new_package_writes_the_template_agent()
  local root = (os.tmpname() .. "-root"):gsub("\\", "/")
  util.mkdir(root .. "/packages")
  util.mkdir(root .. "/docs/architecture")
  util.mkdir(root .. "/.claude/agents")
  local function write(path, text)
    local f = assert(io.open(root .. "/" .. path, "wb"))
    f:write(text)
    f:close()
  end
  write("docs/architecture/overview.md", "<!-- gen-dependency-graph:begin -->\n<!-- gen-dependency-graph:end -->\n")
  write("llms.txt", "<!-- gen-llms-txt:begin -->\n<!-- gen-llms-txt:end -->\n")
  local report = require("tasks.new_package").run({ root = root, args = {
    "scratch", "--layer", "0 — Foundation", "--phase", "0", "--summary", "Scratch things: one, two.",
  } })
  local text = io.open(root .. "/.claude/agents/pkg-scratch.md", "rb")
  local written = text and text:read("a")
  if text then text:close() end
  remove_tree(root)
  os.remove(root:gsub("-root$", ""))
  self:assert_true(report.ok, table.concat(report.problems, "\n"))
  self:assert_equal(agent.render({
    name = "scratch", scope = "Scratch things: one, two.", doc = "docs/roadmap.md", allowed = agent.allowed({}),
  }), written)
end

return T
