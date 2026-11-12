# `hello`

A small JSON API run through `hecate.Application` (the meta-module `hecate`, which re-exports
the kernel surface). It is the example of Phase 2.

## What it demonstrates

| Route | Shows |
|---|---|
| `GET /hello/{name}` | a path parameter validated by a schema (1 to 40 characters), a result represented by a response schema (`{ "message": "Hello, Ada!" }`) |
| `POST /greetings` | JSON content validated by a schema (`name`, optional `language` defaulting to `en`), `422` problem details (RFC 9457) with `source` and a relative `pointer` for each violation, `201` through `hecate.respond` |
| `GET /health` | a route module (`hecate.routes`), the lightweight declaration style |

The two greeting routes are declared by a controller (`hecate.Controller.route`), `/health` by a route
module, so both declaration styles appear. Unknown paths answer a `404` problem details response.
Each `422` entry carries `pointer`, `code` and `source`, never the rejected value or an error
message (`errors.expose_details` defaults to `false`).

```sh
curl -s localhost:8080/hello/Ada
curl -s -X POST localhost:8080/greetings -H 'Content-Type: application/json' -d '{"name":"Ada","language":"fr"}'
curl -s -X POST localhost:8080/greetings -H 'Content-Type: application/json' -d '{"name":""}'
```

The last call answers `422` with `errors[1] = { "pointer": "/name", "source": "content", "code": ... }`.

## Run

Once per clone, from the repository root, build the native modules (`luv` comes with the
bootstrap, `tools/bootstrap`):

```sh
lua tools/run.lua build-native json
lua tools/run.lua build-native http
```

Then, in a POSIX shell from the repository root, put the Hecate packages and the native modules
on the search paths (`luarocks path` gives the paths of `luv`), and run `main.lua` from
`examples/hello` (it adds `src` to the search path):

```sh
eval "$(luarocks path)"
for dir in "$PWD"/packages/*/src; do LUA_PATH="$dir/?.lua;$dir/?/init.lua;$LUA_PATH"; done
export LUA_PATH="$LUA_PATH;;" LUA_CPATH="$PWD/.hecate/rocks/lib/lua/5.5/?.so;$LUA_CPATH;;"
cd examples/hello
HELLO_PORT=8080 lua main.lua
HELLO_PORT=8080 HELLO_WORKERS=4 lua main.lua   # four worker processes (ADR 0023)
```

`HELLO_PORT` defaults to `8080`; the server listens on the loopback interface only.
`HELLO_WORKERS` defaults to `1` (one process serves by itself). Above 1 the process is the
primary: it supervises that many workers, each one `main.lua` started again, and hands them the
connections (`hecate.Application` options `workers` and `strategy`, default `auto`). Ctrl+C
(SIGINT) or SIGTERM stops accepting, lets the requests in flight finish within the grace period
(10 seconds here) and exits; with workers, the primary sends `stop` to each worker, which does
the same, then exits.

## Test

```sh
lua tools/run.lua test examples/hello
```

`tests/hello_test.lua` boots the application in process on an ephemeral port and calls it with
`hecate.http.Client`: the greeting (200), invalid input (422 with `source`), creation (201), the
health route and an unknown path (404). `tests/workers_test.lua` runs the application as the
primary of two workers started from `main.lua` (`round_robin`), checks the answers, then stops it
with `Application:shutdown`.

Both files also check the graceful shutdown: a `POST /greetings` sent with `Expect: 100-continue`
is in flight (the server answered `100 Continue`, its content is not sent yet) when
`Application:shutdown` begins; it is still answered (`201`, with `Connection: close`) once new
connections are refused and the idle connections of every server or worker are closed. The workers
test also checks, through the supervisor's counters, that both workers served connections. The raw
HTTP of these tests is in `tests/helpers/wire.lua`.

CI runs both files on Linux, macOS and Windows whenever the kernel or the example changes.

## Not built yet

- No OpenAPI document (`contract`, later) and no `hecate.project.lua` or `hecate test` /
  `hecate contract lint` (the `cli` and `hecate` packages, Phase 3). The example is run with `lua`
  and tested by the repository harness.
- Greetings are kept in memory only as a counter for `id`; nothing is stored.
