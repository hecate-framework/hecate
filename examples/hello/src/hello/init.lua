-- examples/hello: a small JSON API, run through `hecate.Application`.
global <const> require, pairs, assert

local core = require("hecate.core")
local schema = require("hecate.schema")
local hecate = require("hecate")

local hello = {}

local Greeting = schema.object({ message = schema.string() })
local NewGreeting = schema.object({
  name = schema.string({ min_length = 1, max_length = 40 }),
  language = schema.default(schema.string({ min_length = 2, max_length = 2 }), "en"),
})
local Created = schema.object({ id = schema.integer(), message = schema.string() })

local GREETINGS <const> = { en = "Hello", fr = "Bonjour", es = "Hola" }

--- The controller of the greetings: the declaration style with a class.
---@class hello.GreetingController: hecate.kernel.Controller
local GreetingController = core.class("GreetingController", hecate.Controller)

hecate.Controller.route(GreetingController, {
  method = "GET", path = "/hello/{name}", action = "show", summary = "Greets a name",
  parameters = { path = { name = schema.string({ min_length = 1, max_length = 40 }) } },
  responses = { [200] = Greeting, [422] = hecate.problem.UnprocessableContent },
})
hecate.Controller.route(GreetingController, {
  method = "POST", path = "/greetings", action = "create", summary = "Records a greeting",
  content = { ["application/json"] = NewGreeting },
  responses = { [201] = Created, [422] = hecate.problem.UnprocessableContent },
})

local next_id = 0

-- The dispatcher validates the path parameters and the content before the action runs; the `assert` calls only tell
-- the type checker that these optional fields of `Request` are set here.

---@param request hecate.http.Request
function GreetingController:show(request)
  return { message = ("Hello, %s!"):format(assert(request.parameters.path).name) }
end

---@param request hecate.http.Request
function GreetingController:create(request)
  local content = assert(request.content)
  next_id = next_id + 1
  local word = GREETINGS[content.language] or GREETINGS.en
  return hecate.respond(201, { id = next_id, message = ("%s, %s!"):format(word, content.name) })
end

core.finalise(GreetingController)

--- The route module of the health check: the lightweight declaration style.
---@return hecate.kernel.RouteModule
function hello.health_routes()
  local health = hecate.routes("health")
  health:get("/health", {
    summary = "Liveness probe",
    responses = { [200] = schema.object({ status = schema.string() }) },
    action = function() return { status = "ok" } end,
  })
  return health
end

--- Builds the application. `options` are those of `hecate.Application` (for example `server`, `logger`, `signals`).
---@param options? hecate.kernel.ApplicationOptions
---@return hecate.kernel.Application
function hello.application(options)
  local merged = { routes = { hello.health_routes(), GreetingController } }
  for key, value in pairs(options or {}) do merged[key] = value end
  return hecate.Application(merged)
end

return hello
