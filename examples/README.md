# Example applications

Reference applications, tested in CI, used by tutorials.

| Example | Shows | Phase |
|---|---|---|
| `hello` | route module, validation, problem details, OpenAPI, tests | 2 |
| `controllers` | controllers, services, container, configuration, filters | 3 |
| `crud` | PostgreSQL/MySQL/SQLite, ORM, migrations, transactions, pagination | 4 |
| `concurrency` | fork/join, select, deadlines, channels, external HTTP calls | 3 |
| `auth` | bearer tokens, JWT, policies | 5 |
| `realtime` | Redis publish/subscribe, WebSocket | 5 |

Each example is a complete Hecate project (`hecate.project.lua`, `tests/`) and must pass
`hecate test` and `hecate contract lint` in CI.
