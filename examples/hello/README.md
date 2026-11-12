# `hello`

A small JSON API run through `hecate.kernel.Application`. It is the example of Phase 2.

## What it demonstrates

| Route | Shows |
|---|---|
| `GET /hello/{name}` | a path parameter validated by a schema (1 to 40 characters), a result represented by a response schema (`{ "message": "Hello, Ada!" }`) |
| `POST /greetings` | JSON content validated by a schema (`name`, optional `language` defaulting to `en`), `422` problem details (RFC 9457) with `source` and a relative `pointer` for each violation, `201` through `kernel.respond` |
| `GET /health` | a route module (`kernel.routes`), the lightweight declaration style |

The two greeting routes are declared by a controller (`Controller.route`), `/health` by a route
module, so both declaration styles appear. Unknown paths answer a `404` problem details response.
Reasons for failures never carry values or messages of the errors (`errors.expose_details` is off).

```sh
curl -s localhost:8080/hello/Ada
curl -s -X POST localhost:8080/greetings -H 'Content-Type: application/json' -d '{"name":"Ada","language":"fr"}'
curl -s -X POST localhost:8080/greetings -H 'Content-Type: application/json' -d '{"name":""}'
```

The last call answers `422` with `errors[1] = { "pointer": "/name", "source": "content", "code": ... }`.

## Run

From this directory, with the Hecate packages (`packages/*/src`) on `LUA_PATH` and the native
modules built (`lua tools/run.lua build-native json http`, then `.hecate/rocks` on `LUA_CPATH`):

```sh
HELLO_PORT=8080 lua main.lua
HELLO_PORT=8080 HELLO_WORKERS=4 lua main.lua   # four worker processes (ADR 0023)
```

`HELLO_PORT` defaults to `8080`; the server listens on the loopback interface only.
`HELLO_WORKERS` defaults to `1` (one process serves by itself). Above 1 the process is the
primary: it supervises that many workers, each one `main.lua` started again, and hands them the
connections (`kernel.Application` options `workers` and `strategy`, default `auto`). Ctrl+C
(SIGINT) or SIGTERM stops accepting, lets the requests in flight finish (up to 10 seconds) and
exits; with workers, the primary asks each worker to drain, then exits.

## Test

```sh
lua tools/run.lua test examples/hello
```

`tests/hello_test.lua` boots the application in process on an ephemeral port and calls it with
`hecate.http.Client`: the greeting (200), invalid input (422 with `source`), creation (201), the
health route and an unknown path (404). `tests/workers_test.lua` runs the application as the
primary of two workers started from `main.lua` (`round_robin`), checks the answers, then stops it
with `Application:shutdown`.

Both files also check the graceful shutdown: a `POST /greetings` whose content is only half sent
when `Application:shutdown` begins is still answered (`201`, with `Connection: close`), while new
connections are already refused. In process the server drains it; with workers, the worker that
holds the connection does. The raw HTTP of these tests is in `tests/helpers/wire.lua`.

CI runs both files on Linux, macOS and Windows whenever the kernel or the example changes.

## Not built yet

- No OpenAPI document (`contract`, later) and no `hecate.project.lua` or `hecate test` /
  `hecate contract lint` (the `cli` and `hecate` packages, Phase 3). The example is run with `lua`
  and tested by the repository harness.
- Greetings are kept in memory only as a counter for `id`; nothing is stored.
