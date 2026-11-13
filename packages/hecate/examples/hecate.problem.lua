-- Domain errors as problem details (RFC 9457). An action returns a problem,
-- or raises one from any depth; both answer application/problem+json. An
-- error that is not a problem answers a generic 500 that names nothing.
local schema = require("hecate.schema")
local http = require("hecate.http")
local json = require("hecate.json")
local hecate = require("hecate")

-- An application's own problem class: a status, a title and a type URI.
local OutOfStock = hecate.problem.define("OutOfStock", {
  status = 409, title = "Out of stock",
  type = "https://example.com/problems/out-of-stock",
})
print(OutOfStock.code)
-- Prints: app.problem.OutOfStock

local STOCK = { lamp = 0, desk = 3 }

local function reserve(item)
  if STOCK[item] == nil then
    -- Raised deep in the domain code: the guard of the kernel maps it.
    error(hecate.problem.NotFound { detail = "No such item." })
  end
  if STOCK[item] == 0 then
    return OutOfStock { detail = "Nothing left.", extensions = { item = item } }
  end
  if item == "desk" then error("database connection lost: 10.0.0.5") end
end

local orders = hecate.routes("orders")
orders:post("/orders/{item}", {
  parameters = { path = { item = schema.string({ max_length = 20 }) } },
  responses = {
    [204] = true, [404] = hecate.problem.NotFound, [409] = OutOfStock,
  },
  action = function(request) return reserve(request.parameters.path.item) end,
})

local serve = hecate.Application({ routes = { orders } }):boot()
-- Asks the application in-process; returns the status and the decoded JSON.
local function post(target)
  local request = http.Request({
    method = "POST", target = target, fields = http.Fields(),
  })
  local response = serve(request)
  return response.status, json.decode(response.content --[[@as string]])
end

local status, body = post("/orders/lamp")
print(status, body.type)
-- Prints: 409	https://example.com/problems/out-of-stock
print(body.title, body.detail, body.item)
-- Prints: Out of stock	Nothing left.	lamp
status, body = post("/orders/chair")
print(status, body.type, body.title, body.detail)
-- Prints: 404	about:blank	Not Found	No such item.
status, body = post("/orders/desk")
print(status, body.title)
-- Prints: 500	Internal Server Error
print(body.detail)
-- Prints: The server could not process the request.
