# `hello`

A small JSON API run through `hecate.kernel.Application`. It is the example of Phase 2.

## What it demonstrates

| Route | Shows |
|---|---|
| `GET /hello/{name}` | a path parameter validated by a schema (1 to 40 characters), a result represented by a response schema (`{ "message": "Hello, Ada!" }`) |
| `POST /greetings` | JSON content validated by a schema (`name`, optional `language` defaulting to `en`), `422` problem details (RFC 9457) with `source` and a relative `pointer` for each violation, `201` through `kernel.results.respond` |
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
```

`HELLO_PORT` defaults to `8080`; the server listens on the loopback interface only. Ctrl+C
(SIGINT) or SIGTERM stops accepting, lets the requests in flight finish (up to 10 seconds) and exits.

## Test

```sh
lua tools/run.lua test examples/hello
```

`tests/hello_test.lua` boots the application in process on an ephemeral port and calls it with
`hecate.http.Client`: the greeting (200), invalid input (422 with `source`), creation (201), the
health route and an unknown path (404).

## Not built yet

- **Single process only.** Multi-process workers (ADR 0023) are not built. The Phase 2 exit
  criterion, running on three platforms with N workers, is therefore still open for this example.
- No OpenAPI document (`contract`, later) and no `hecate.project.lua` or `hecate test` /
  `hecate contract lint` (the `cli` and `hecate` packages, Phase 3). The example is run with `lua`
  and tested by the repository harness.
- Greetings are kept in memory only as a counter for `id`; nothing is stored.
