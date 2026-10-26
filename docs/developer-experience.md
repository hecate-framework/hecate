# Target developer experience

This document describes what using Hecate should feel like. It is the north star for
API design. **Code below is illustrative**: names and signatures are settled by ADRs and
specifications, which take precedence. In particular, classes are declared with
`core.class` and finalised with `core.finalise` (ADR 0007); a `hecate.class` alias is
not decided ([OQ-57](open-questions.md)).

## Installation and a new project

```sh
# One self-contained executable; it embeds its own Lua 5.5 (ADR 0010)
curl -fsSL https://hecate.theandre.dev/install.sh | sh        # Linux, macOS
winget install Hecate.Hecate                          # Windows (or scoop)

hecate new acme-api        # scaffolds the project, installs the Lua 5.5 toolchain
cd acme-api
hecate install             # resolves and installs dependencies (LuaRocks), writes hecate.lock
hecate serve --watch       # development server with reload
```

```text
$ hecate version
Hecate 0.3.0 (Lua 5.5.1, LuaRocks 3.x, libuv 1.x) — linux-x86_64
```

## Project layout

```text
acme-api/
  hecate.project.lua      project manifest (ADR 0009)
  hecate.lock             exact resolved versions
  config/
    default.lua
    production.lua
  src/
    application.lua       composition root
    users/
      module.lua          feature module: routes, services, migrations
      user.lua            entity class
      user_repository.lua
      user_controller.lua
  migrations/
  tests/
    users/user_controller_test.lua
  lua_modules/            project-local rocks tree (ignored by git)
```

## Manifest

```lua
-- hecate.project.lua (evaluated in an empty, sandboxed environment)
return {
  name    = "acme-api",
  version = "0.1.0",
  lua     = "5.5",
  dependencies = {
    ["hecate"]            = "~> 0.3",
    ["hecate-postgresql"] = "~> 0.3",
    ["hecate-orm"]        = "~> 0.3",
  },
  development_dependencies = {
    ["hecate-test"] = "~> 0.3",
  },
}
```

Version constraints use LuaRocks syntax as-is.

## A controller (object-oriented style)

```lua
local hecate = require "hecate"
local core   = require "hecate.core"
local schema = require "hecate.schema"
local User   = require "users.user"

---@class UserController : hecate.Controller
---@field private repository UserRepository
local UserController = core.class("UserController", hecate.Controller)

UserController.prefix       = "/users"
UserController.dependencies = { repository = "users.UserRepository" }

UserController:route {
  method     = "GET",
  path       = "/{id}",
  summary    = "Fetch a user",
  parameters = { path = { id = schema.integer { minimum = 1 } } },
  responses  = { [200] = User.representation, [404] = hecate.problem.NotFound },
  action     = "show",
}

---@param request hecate.Request
function UserController:show(request)
  local user = self.repository:find(request.parameters.path.id)   -- suspends during I/O
  if user == nil then
    return hecate.problem.NotFound { detail = "No such user." }
  end
  return user
end

core.finalise(UserController)   -- required before the class is instantiated

return UserController
```

## A route module (lightweight style)

```lua
local hecate = require "hecate"
local schema = require "hecate.schema"

local health = hecate.routes "health"

health:get "/health" {
  summary   = "Liveness probe",
  responses = { [200] = schema.object { status = schema.literal "ok" } },
  action    = function(request) return { status = "ok" } end,
}

return health
```

Both styles produce the same route table, so validation, contracts and documentation
behave identically.

## Intended concurrency

```lua
local reactor = require "hecate.reactor"

function DashboardController:show(request)
  local user = self.users:find(request.parameters.path.id)

  local orders, rate = reactor.join(
    reactor.fork(function() return self.orders:of(user) end),
    reactor.fork(function() return self.rates:current("EUR") end)
  )

  local statistics = reactor.deadline(2.0, function()
    return self.statistics:compute(user)
  end)

  return { user = user, orders = orders, rate = rate, statistics = statistics }
end
```

## Entities and the ORM

```lua
local core = require "hecate.core"
local orm  = require "hecate.orm"

---@class User : hecate.orm.Entity
---@field id integer
---@field email string
local User = core.class("User", orm.Entity)

User.relation = orm.relation "users" {
  id    = orm.attribute.integer { primary = true, generated = true },
  email = orm.attribute.string { max_length = 254, unique = true },
}

core.finalise(User)
```

```lua
-- inside a service
local unit = self.orm:unit_of_work()
local user = User { email = "ada@example.org" }
unit:persist(user)
unit:commit()        -- one transaction, flushed in dependency order
```

## Tests

```lua
local test = require "hecate.test"

local UserControllerTest = test.Case("UserControllerTest")

function UserControllerTest:test_unknown_user_is_not_found()
  local response = self.client:get("/users/999")
  self:assert_status(404, response)
  self:assert_conforms(response)     -- checked against the generated contract
end

return UserControllerTest
```

```text
$ hecate test
UserControllerTest ........ 8 passed
contract conformance ...... 42 routes, 0 violations
```

## Contracts and documentation

```text
$ hecate contract export --format json > openapi.json
$ hecate contract diff v0.2.0        # breaking-change detection between two versions
$ hecate doc build                   # code reference + API reference, static HTML
```

In development, the running application serves `/openapi.json` and an interactive
reference page.
