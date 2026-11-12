# Example applications

Reference applications, tested in CI, used by tutorials.

| Example | Shows | Phase |
|---|---|---|
| `hello` | route module and controller, validation, problem details, workers, graceful shutdown, tests (OpenAPI from Phase 3) | 2 |
| `controllers` | controllers, services, container, configuration, filters | 3 |
| `crud` | PostgreSQL/MySQL/SQLite, ORM, migrations, transactions, pagination | 4 |
| `concurrency` | fork/join, select, deadlines, channels, external HTTP calls | 3 |
| `auth` | bearer tokens, JWT, policies | 5 |
| `realtime` | Redis publish/subscribe, WebSocket | 5 |

From Phase 3 on, each example is a complete Hecate project (`hecate.project.lua`, `tests/`) and
must pass `hecate test` and `hecate contract lint` in CI. Until the `cli`, `test` and `openapi`
packages exist (Phase 3), an example is a plain Lua program run with `lua main.lua` and tested by
the repository harness: `lua tools/run.lua test examples/<name>`. CI runs `hello` on Linux, macOS
and Windows whenever the kernel or the example changes. The `cli` item of Phase 3 turns `hello`
into a project (`hecate.project.lua`, OpenAPI contract) once those commands exist.
