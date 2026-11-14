---
description: Turn the errors of your domain into RFC 9457 problem details with hecate.problem - built-in classes, problem.define, returning or raising a problem, the guard, and errors.expose_details.
hecate: "0.x"
lua: "5.5"
order: 16
---

# Map domain errors to problem details

This guide shows how an application answers its errors as
[problem details](../reference/glossary.md#http) ([RFC 9457](https://www.rfc-editor.org/rfc/rfc9457)): a JSON
object with the media type `application/problem+json`. It is written for hecate 0.x and Lua 5.5, and assumes you
have an `Application` with routes (see [Route requests](route-requests.md)).

The problem classes live in `hecate.problem` (the same table as `hecate.kernel.problem`). A problem is a
[class](../reference/glossary.md#object-model-and-architecture) of the object model and a subclass of
`hecate.core.Error`, so you can return it or raise it.

## Use a built-in class

`hecate.problem` has one class per common status:

| Class | Status | Class | Status |
|---|---|---|---|
| `BadRequest` | 400 | `ContentTooLarge` | 413 |
| `Unauthorized` | 401 | `UnsupportedMediaType` | 415 |
| `Forbidden` | 403 | `UnprocessableContent` | 422 |
| `NotFound` | 404 | `TooManyRequests` | 429 |
| `MethodNotAllowed` | 405 | `InternalServerError` | 500 |
| `NotAcceptable` | 406 | `BadGateway` | 502 |
| `RequestTimeout` | 408 | `ServiceUnavailable` | 503 |
| `Conflict` | 409 | `GatewayTimeout` | 504 |
| `Gone` | 410 | | |
| `PreconditionFailed` | 412 | | |

The title of each class is the reason phrase of its status (`Not Found`) and its `type` is `about:blank`. Its stable
code is `hecate.problem.<Name>`, for example `hecate.problem.NotFound`.

Build an occurrence with two optional fields:

```lua
return hecate.problem.NotFound {
  detail = "No order 42.",
  extensions = { order = 42 },
}
```

- `detail` is a string you write for the client. It is never an error message.
- `extensions` are extra members of the JSON object (RFC 9457, section 3.2). The names `type`, `title`, `status`,
  `detail` and `instance` are reserved and refused with an `ArgumentError`, as is any field other than `detail`,
  `extensions` and `fields`. A function, a coroutine, a userdata or a number that is not finite is refused too at the
  first level of `extensions`, because JSON cannot carry it; nested deeper, it makes the answer a generic `500`,
  logged at `error`.

## Declare your own problem

`hecate.problem.define(name, { status, title, type?, code? })` declares a class for an error of your domain:

- `status` is an integer from 400 to 599 and `title` a non-empty string;
- `type` is a URI reference that identifies the problem (default `about:blank`);
- `code` defaults to `app.problem.<name>`. A code in the `hecate.` namespace belongs to the framework and is refused.

Each of these mistakes raises an `ArgumentError` at once, when the module that declares the class loads.

## Return or raise a problem

The example below declares `OutOfStock`, returns it from a domain function, raises `NotFound` from the same
function, and shows what an error that is not a problem gives.

<!-- example: packages/hecate/examples/hecate.problem.lua -->
```lua
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
```

- **Return** a problem when the action decides the answer. The result of the action goes through the same
  serialisation as a value, and a problem becomes `application/problem+json`.
- **Raise** a problem (`error(NotFound { ... })`) from code deep below the action, where returning is awkward. The
  guard of the kernel catches it and answers it the same way.
- **Any other error** (a Lua error, a `hecate.core.Error`) answers a generic `500`. Its message never reaches the
  client: here, `database connection lost: 10.0.0.5` stays on the server, in the log (see below).

The answer has `type`, `title`, `status`, the `detail` you gave and the extension members. It has no `instance`
member.

## Add header fields to a problem

Some answers need a header field ([RFC 9110](https://www.rfc-editor.org/rfc/rfc9110)): `WWW-Authenticate` on a
`401` (sections 11.6.1 and 15.5.2), `Allow` on a `405` (section 15.5.6), `Retry-After` on a `429` or a `503`
(section 10.2.3). Give them in `fields`, a name to a string, or to a list of strings for several field lines:

```lua
return hecate.problem.Unauthorized {
  fields = { ["WWW-Authenticate"] = 'Bearer realm="api"' },
}
```

The fields go to the response, never to the JSON object nor to the contract of the route; they apply to a problem
you return or raise. A name that is not a token or a value with a control character raises an `ArgumentError` when
the problem is built, and so do `Content-Type`, `Content-Length`, `Transfer-Encoding` and `Connection`, which the
kernel sets itself.

## Declare the problems of a route

The `responses` table of a route accepts a problem class for a status, as the example does with
`[404] = hecate.problem.NotFound`. That records the answer in the route table, the data from which the OpenAPI
document is planned (Phase 3). It changes nothing at run time: an action can return or raise a problem that its route
does not declare.

## Know what the guard does

The guard (`problems.guard`) wraps every request, inside the global filters. It turns what escapes the filters and
the action into a response:

| Raised | Answer |
|---|---|
| a problem | its own status, title, type, detail and extensions |
| an error of `hecate.http` that carries a client status (a malformed form, content over the limit) | that status |
| anything else | a generic `500` |

The `422` of invalid inputs does not come from the guard: the step that reads the inputs answers it before the
action runs, and does not log it. It lists one entry per
[violation](../reference/glossary.md#types-and-validation), at most 100: `pointer` (a JSON Pointer, RFC 6901),
`source` (`path`, `query`, `header`, `cookie` or `content`) and `code`. A
`ValidationError` raised by your own code, by `schema:check` for example, is not about the request: it is a `500`.
To answer a `422` from an action, return or raise `UnprocessableContent`.

Cancellation and deadline errors are never caught: they belong to the [scope](../reference/glossary.md#concurrency)
that raised them.

> [!NOTE] Where the guard logs
> The guard logs a failure through the logger of the application: the `logger` option, or the one the kernel builds
> from a `configuration`. Without either, it logs through the default logger of `hecate.log`, on the standard error
> stream, so a `500` is never silent. A problem below 500 is a normal answer and is never logged; a problem from 500
> is logged at `error`.

The logged record carries the message of the error, its class (`error_class`) and code (`error_code`), the method, the
path without the query string, and the traceback where it was raised. While `errors.expose_details` is `false`, the
causes of the error are named by class and code only, never by their messages.

## Show details in development

The configuration key `errors.expose_details` (default `false`; the `expose_details` option of `Application`) adds
internal details to the answers:

- each `422` entry also carries the `message` of its violation;
- a generic `500` carries a `debug` member: `{ error = <class name>, message = <text>, traceback = <when known> }`.

The `detail` and the extensions of a problem are always shown, with or without it: you chose them. Set the key to
`true` in `config/development.lua` and `config/test.lua` only. When it is `true` in the environment `production`,
the application logs the warning `expose_details_in_production` at boot. See
[Configure an application](configure-an-application.md).

## Answer a problem without the kernel

An action given directly to `hecate.http.Server` has no guard. It builds its problem details with
`http.problem.response(status, detail?)`, as [Serve HTTP](serve-http.md#answer-errors-with-problem-details) shows.

## See also

- [Filters](filters.md): a filter can answer a problem before the action runs.
- [Validate values with schemas](validate-with-schemas.md): violations, codes and JSON Pointers.
- [Before going to production](before-going-to-production.md): error details and logging.
