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

## As a Hecate project

`examples/hello` is a Hecate project (`hecate.project.lua`): with the executable built (`lua tools/run.lua build-cli`) and the
packages of the repository copied into `lua_modules` (`lua tools/run.lua link-modules examples/hello`, which stands in for
`hecate install` until the rocks are published), from this directory:

```sh
hecate test                                              # the tests of tests/hello_test.lua
hecate contract export --output=openapi.json && hecate contract lint openapi.json
HELLO_PORT=8080 hecate serve                             # runs main.lua
hecate doc build --yes                                   # the documentation site, in docs/dist
```

The repository harness runs the same tests (`lua tools/run.lua test examples/hello`); `workers_test.lua` and
`docs_build_test.lua` need that harness and are skipped by `hecate test`. `tools/tests/cli_e2e_test.lua` runs these commands in
CI, on the three platforms.

## Run

Once per clone, from the repository root, install `luv` (the bootstrap installs only Lua and
LuaRocks; building `luv` needs CMake and a C compiler) and build the native modules, all into
`.hecate/rocks`:

```sh
luarocks --tree .hecate/rocks install luv 1.53.0-0
lua tools/run.lua build-native json
lua tools/run.lua build-native http
```

Then, in a POSIX shell from the repository root, put the Hecate packages and the native modules
on the search paths, and run `main.lua` from
`examples/hello` (it adds `src` to the search path):

```sh
eval "$(luarocks path)"
for dir in "$PWD"/packages/*/src; do LUA_PATH="$dir/?.lua;$dir/?/init.lua;$LUA_PATH"; done
export LUA_PATH="$LUA_PATH;;" LUA_CPATH="$PWD/.hecate/rocks/lib/lua/5.5/?.so;$LUA_CPATH;;"
cd examples/hello
HELLO_PORT=8080 lua main.lua
HELLO_PORT=8080 HELLO_WORKERS=4 lua main.lua   # four worker processes (ADR 0023)
```

Each response is logged on the standard error stream, through the default logger: method,
path without the query string (a query can carry secrets), status, bytes and duration, for example
`INFORMATIONAL [hecate] GET /hello/Ada -> 200 bytes=... duration_ms=0 status=200`. This is the
`on_response` hook of `hecate.http.Server`, set in `main.lua`; the framework has no access log of
its own yet.

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

`tests/docs_build_test.lua` builds the documentation site (below) into temporary directories with the real file
system and the native module of `doc`: no problem, the home page, the endpoints and request-flow pages, the logos,
the favicons, `hello-theme.css` (linked) and `llms.txt` exist, and two builds are byte-identical. It is skipped
without the native module, except in CI, whenever `doc` or the site of the example changes
(`lua tools/run.lua test examples/hello:docs_build_test` runs it alone).

## Documentation site

`docs/` holds the documentation of the example, written by hand. The pages are documentation for the team that
changes the example, so they are the content tree of the `maintainer` audience, `docs/maintainer/`: guides in
`docs/maintainer/en/` and `docs/maintainer/public/` with the logo, the favicon, the fonts and the CSS file of the
theme. The site configuration is the one file of the project, `docs/site.lua`. There is no `docs/user/` tree: the
default of `generate_project_documentation` builds the `maintainer` tree only, and the site is written to
`docs/dist/maintainer/`. It is a
showcase of the theme extension points of `hecate.doc`, in a plain, neutral style (white and slate greys, one sky
accent, thin borders, small radii): its own palette in light and dark, its own radii and sidebar width, the Inter
family (SIL OFL 1.1, Latin subset in `docs/maintainer/public/fonts/`, loaded by the `@font-face` of the CSS file; recorded in
`THIRD_PARTY_NOTICES`) for the text and a system monospace stack for code, its own logo and favicon (each in a
light and a dark variant, through `logo_path` and `favicon_path`). The sidebar marker (`sidebar_marker`) is left off, which
is the default. It also turns on `llms.txt` (`generate_llms_txt`).
Build it from the repository root, with `luv` installed and the native module of `doc` built (`lua tools/run.lua
build-native doc`), and the Hecate packages on the search path (`build_docs.lua` adds them itself):

```sh
lua examples/hello/build_docs.lua            # writes examples/hello/docs/dist/maintainer (git-ignored)
lua examples/hello/build_docs.lua /tmp/site  # or elsewhere
```

`build_docs.lua` calls `hecate.doc.generate_project_documentation` with the project directory and nothing else:
the guides (`docs/<audience>/`, here `docs/maintainer/`), the site configuration (`docs/site.lua`) and the output
(`docs/dist/<audience>/`) are the defaults of the conventional layout. An output directory in the command line is relative to `examples/hello` unless it is absolute.
The build is strict (`fail_on_problems`): a broken link fails it. Serve the output with any static server. The page "Theme tokens" of the
website lists every property the CSS file can override.

## Not built yet

- No OpenAPI document (`contract`, later) and no `hecate.project.lua` or `hecate test` /
  `hecate contract lint` (the `cli` and `hecate` packages, Phase 3). The example is run with `lua`
  and tested by the repository harness.
- Greetings are kept in memory only as a counter for `id`; nothing is stored.
