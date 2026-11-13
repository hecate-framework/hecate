---
description: Turn the errors of your domain into RFC 9457 problem details with hecate.problem - built-in classes, problem.define, returning or raising a problem, the guard, and errors.expose_details.
hecate: "0.x"
lua: "5.5"
order: 16
---

# Map domain errors to problem details

This guide shows how an application answers its errors as problem details. It is written for hecate 0.x and Lua 5.5.
It assumes you have an `Application` with routes (see [Route requests](route-requests.md)).

[Problem details](../reference/glossary.md#http) are the standard shape of an HTTP error
([RFC 9457](https://www.rfc-editor.org/rfc/rfc9457)). A problem is a JSON object, sent with the media type
`application/problem+json`. It names the kind of error and says what went wrong for this request.

In hecate, the problem classes live in `hecate.problem`. That is the same table as `hecate.kernel.problem`. Each
problem is a [class](../reference/glossary.md#object-model-and-architecture), a template for objects with shared
behaviour. It is also a subclass of `hecate.core.Error`, so you can return it or raise it.

## Use a built-in class

`hecate.problem` has one class per common status: `NotFound` for `404`, `Conflict` for `409`, and so on. You build
an occurrence by calling the class with a table:

```lua
return hecate.problem.NotFound {
  detail = "No order 42.",
  extensions = { order = 42 },
}
```

Both fields of the table are optional:

- `detail` is a string you write for the client. It is never an error message.
- `extensions` are extra members of the JSON object (RFC 9457, section 3.2).

The extensions are checked when the problem is built. Each of these raises an `ArgumentError`:

- a reserved name: `type`, `title`, `status`, `detail` or `instance`;
- at the first level of `extensions`, a value that JSON cannot carry: a function, a coroutine, a userdata or a number
  that is not finite.

A value nested deeper is checked only when the problem is answered. If JSON cannot carry it, the answer is the
generic `500` and the failure is logged.

A field of the table other than `detail`, `extensions` and `fields` raises an `ArgumentError` too. The `fields` field
is described in [Add header fields to a problem](#add-header-fields-to-a-problem).

Here are all the built-in classes:

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

The title of each class is the reason phrase of its status, such as `Not Found`. Its `type` is `about:blank`. Its
stable code is `hecate.problem.<Name>`, for example `hecate.problem.NotFound`.

## Declare your own problem

An error of your domain deserves a class of its own. `hecate.problem.define(name, spec)` declares one:

```lua
local OutOfStock = hecate.problem.define("OutOfStock", {
  status = 409, title = "Out of stock",
  type = "https://example.com/problems/out-of-stock",
})
print(OutOfStock.code)
-- Prints: app.problem.OutOfStock
```

The `spec` table has four fields:

- `status` is an integer from 400 to 599. It is required.
- `title` is a non-empty string. It is required.
- `type` is a URI reference that identifies the problem. It defaults to `about:blank`.
- `code` defaults to `app.problem.<name>`. A code in the `hecate.` namespace belongs to the framework and is refused.

Each mistake raises an `ArgumentError` at once, when the module that declares the class loads.

## Return or raise a problem

An [action](../reference/glossary.md#object-model-and-architecture), the function that serves a request, has two
ways to answer with a problem. It can return the problem, or it can raise it.

The example below declares `OutOfStock` and returns it from a domain function. The same function raises `NotFound`.
It also shows what an error that is not a problem gives.

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

Use each way where it fits:

- **Return** a problem when the action decides the answer. The result of the action goes through the same
  serialisation as a value, and a problem becomes `application/problem+json`.
- **Raise** a problem (`error(NotFound { ... })`) from code deep below the action, where returning is awkward. The
  guard of the kernel catches it and answers it the same way.

**Any other error** answers a generic `500`: a Lua error, or a `hecate.core.Error` that is not a problem. Its message
never reaches the client. Here, `database connection lost: 10.0.0.5` stays on the server, in the log (see
[Know what the guard does](#know-what-the-guard-does)).

The answer to a problem has the members `type`, `title` and `status`. It also has the `detail` you gave and the
extension members. It has no `instance` member.

## Add header fields to a problem

Some answers need a header field ([RFC 9110](https://www.rfc-editor.org/rfc/rfc9110)). Give it in `fields`:

```lua
return hecate.problem.Unauthorized {
  fields = { ["WWW-Authenticate"] = 'Bearer realm="api"' },
}
```

`fields` maps a name to a string. For several field lines, map the name to a list of strings.

RFC 9110 asks for these fields:

| Answer | Field | RFC 9110 |
|---|---|---|
| `401` | `WWW-Authenticate` | sections 11.6.1 and 15.5.2 |
| `405` | `Allow` | section 15.5.6 |
| `429` or `503` | `Retry-After` | section 10.2.3 |

The fields go to the response. They never go to the JSON object, nor to the contract of the route. They apply to a
problem you return and to one you raise.

Some fields are refused with an `ArgumentError` when the problem is built:

- a name that is not a token;
- a value with a control character;
- `Content-Type`, `Content-Length`, `Transfer-Encoding` and `Connection`, which the kernel sets itself.

## Declare the problems of a route

The `responses` table of a route accepts a problem class for a status. The example does it with
`[404] = hecate.problem.NotFound`.

That records the answer in the [route table](../reference/glossary.md#http), the list of route declarations the
router compiles at boot. The OpenAPI document is planned to be built from that data (Phase 3).

Declaring a problem class changes nothing at run time. An action can return or raise a problem that its route does
not declare.

## Know what the guard does

The guard (`problems.guard`) turns what escapes the filters and the action into a response. It wraps every request,
inside the global [filters](../reference/glossary.md#object-model-and-architecture). A filter is an object that wraps
the action of a route; [Filters](filters.md) explains them.

| Raised | Answer |
|---|---|
| a problem | its own status, title, type, detail and extensions |
| an error of `hecate.http` that carries a client status (a malformed form, content over the limit) | that status |
| anything else | a generic `500` |

A `ValidationError` belongs to "anything else". One raised by your own code, by `schema:check` for example, is not
about the request: it is a `500`. To answer a `422` from an action, return or raise `UnprocessableContent`.

Cancellation and deadline errors are never caught. They belong to the [scope](../reference/glossary.md#concurrency)
that raised them, the structured-concurrency region that owns the computation.

### The 422 of the inputs

The `422` for invalid inputs does not come from the guard. Before the action runs, the kernel reads and validates
the inputs of the request against the schemas of the route. When they do not conform, it answers the `422` at once.

That answer lists one entry per [violation](../reference/glossary.md#types-and-validation), at most 100. A violation
is one reason a value does not conform to a schema. Each entry has three members:

- `pointer`, a JSON Pointer (RFC 6901);
- `source`: `path`, `query`, `header`, `cookie` or `content`;
- `code`, the stable code of the violation.

### Where the guard logs

The guard logs a failure through the logger of the application. That is the `logger` option, or the logger the
kernel builds from a `configuration`. Without either, it logs through the default logger of `hecate.log`, on the
standard error stream. So a `500` is never silent.

> [!NOTE] Which failures are logged
> A problem below 500 is a normal answer and is never logged. A problem from 500 is logged at `error`, as is any
> other failure answered with a `500`. A client-caused error answered below 500, such as content over the limit, is
> logged at `warning`.

The logged record carries:

- the message of the error;
- its class (`error_class`) and its code (`error_code`);
- the method, and the path without the query string;
- the traceback where the error was raised.

While `errors.expose_details` is `false`, the causes of the error are named by class and code only, never by their
messages.

## Show details in development

The configuration key `errors.expose_details` adds internal details to the answers. Its default is `false`. The
`expose_details` option of `Application` sets it too.

When it is `true`:

- each `422` entry also carries the `message` of its violation;
- a generic `500` carries a `debug` member: `{ error = <class name>, message = <text>, traceback = <when known> }`.

The `detail` and the extensions of a problem are always shown, with or without it. You chose them.

Set the key to `true` in `config/development.lua` and `config/test.lua` only. When it is `true` in the
[environment](../reference/glossary.md#configuration) `production`, the application logs the warning
`expose_details_in_production` at boot. The environment is the name of the deployment, which selects
`config/<environment>.lua`. See [Configure an application](configure-an-application.md).

## Answer a problem without the kernel

An action given directly to `hecate.http.Server` has no guard. It builds its problem details with
`http.problem.response(status, detail?)`, as [Serve HTTP](serve-http.md#answer-errors-with-problem-details) shows.

## See also

- [Filters](filters.md): a filter can answer a problem before the action runs.
- [Validate values with schemas](validate-with-schemas.md): violations, codes and JSON Pointers.
- [Before going to production](before-going-to-production.md): error details and logging.
