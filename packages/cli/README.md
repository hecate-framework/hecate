# `hecate-cli`

> The `hecate` command: toolchains, projects, dependencies (LuaRocks), development server, tests, contracts, documentation, migrations, scaffolding, packaging.

| | |
|---|---|
| Module | `hecate.cli` |
| Rock | `hecate-cli` |
| Layer | Tooling |
| Roadmap phase | 3 |
| Status | in progress — the `hecate` executable (C host, LuaRocks embedded, `build-cli`, three platforms), dispatcher, argument parser, `--help`, `help`, `--json`, exit codes, `version`, shell completion, the manifest, the lockfile format, SHA-256, LuaRocks constraints and orchestration, `new`, `init`, `install [--frozen]`, `add`, `remove`, `update`, `outdated`, `test`, `serve`, `run`, `contract`, `doc build`, `generate meta`, `generate systemd`, `package`, `doctor`; toolchains, migrations and workflows to do |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`reactor`](../reactor), [`log`](../log), [`json`](../json), [`schema`](../schema); the rocks of the user's project (`test`, `doc`, `openapi`, ...) are run by the project's interpreter, not linked |
| Used by | — |
| Native code | self-contained executable embedding Lua 5.5 and what the CLI itself needs (OQ-13) |
| Specification | [cli-and-packaging.md](../../docs/architecture/cli-and-packaging.md) |
| Decisions | [ADR 0009](../../docs/adr/0009-project-manifest.md), [ADR 0010](../../docs/adr/0010-self-contained-cli-and-managed-toolchains.md) |
| Agent | [`pkg-cli`](../../.claude/agents/pkg-cli.md) |
| Repository | read-only mirror `hecate-framework/hecate-cli`, generated from this directory (ADR 0017) |

## Responsibilities

- all commands in cli-and-packaging.md
- manifest evaluation in a sandbox and validation
- lockfile generation and verification
- LuaRocks orchestration with isolated configuration
- toolchain installation per platform
- project templates
- workflow generation (`hecate generate workflow ci|contract|docs-pages|release`), including publication of the documentation to GitHub Pages
- `--json` output for every command

## Non-goals

- replacing LuaRocks
- carrying the framework: `kernel`, `test`, `doc`, `openapi`, `migration` and the drivers are dependencies of the
  user's project, installed by `hecate install` and run by the project's interpreter; the `hecate` executable starts
  that interpreter and loads none of them (owner decision of 2026-11-14, [spike OQ-13](../../docs/spikes/OQ-13-standalone-executable.md))

## Standards and references

- sha256 through the `digest` rock behind a one-module seam, [ADR 0028](../../docs/adr/0028-cli-sha256-rock-behind-a-seam.md)
- LuaRocks rockspec format
- SemVer 2.0.0

## Public API

- `cli.run(args, options)`: runs one command line, returns the exit code (0 ok, 1 command failed, 2 usage error).
- `cli.parse(args, commands)`: global flags, command selection (one or two words) and options, raising `ArgumentError`.
- `cli.commands`: the commands implemented so far (`version` and `--version`, `doctor`, `new`, `init`, `install`, `add`, `remove`, `update`, `outdated`, `test`, shell completion).
- `cli.completion`: `complete(words, commands)` (candidates for a partial command line) and `script(shell)`; commands `completion <shell>` and the hidden `__complete`.
- `cli.templates`: `templates` (by name: `api`, the default, and `minimal`), `names()` and `module_name(name)`; `hecate new <name> [--template api|minimal]` writes `<name>/` and refuses an existing directory: `minimal` is a manifest (with the `doc` section of the conventional layout), `docs/site.lua` and a first page `docs/maintainer/en/index.md` (so that `hecate doc build` works at once), `main.lua`, one route module (the health check), a test, `.gitignore` and a README; `api` (the default) adds a resource (`items`: list, show, create over an in-memory store) with its schemas, its route module, tests, and the `contract` section of the manifest. `--ci github` waits for `hecate generate workflow` (it needs the setup action of the project, not created yet); the CLI generates no Dockerfile (OQ-133); `crud` comes with the ORM and the migrations. The executable carries the headers of its Lua (`hecate.cli.lua_headers`): `install` and `update` unpack them into `.hecate/lua/include` and set `LUA_INCDIR`, so that a C rock builds without a system Lua. `hecate package [--output <file>]` writes the release archive of the project (`hecate.project.lua`, `hecate.lock`, `main.lua`, `src/`, `config/`, `lua_modules/` and a `RELEASE` file; `<name>-<version>-<platform>.tar.gz`, a `.zip` on Windows, and its `.sha256`), for a server without Docker: run `hecate install --frozen` first, on the platform of the server. `hecate generate meta [--namespace <name>] [--output <file>] [--force]` writes the LuaLS declaration file of the schemas of the contract of the application (`meta/<module>.schemas.lua`; list `meta` in `workspace.library` of `.luarc.json`; OQ-121). `hecate generate systemd [--user <name>] [--workers <n>] [--executable <path>] [--output <file>] [--force]` prints (or writes) the unit file that runs `hecate serve` as a service: working directory, `SIGTERM` to stop (35 s), `SIGHUP` to reload, restart on failure. `hecate init [--name <name>]` writes the same template into the current directory, keeps every existing file and refuses a directory that already has `hecate.project.lua`.
- `cli.doctor`: `run(runtime, probes, project?)` (the checks: Lua 5.5, LuaRocks, luv, the native codec, SHA-256, a C compiler, the manifest and lockfile of the current directory) and `summary(checks)`; the `hecate doctor` command exits 1 on a failed check, warnings do not.
- `cli.manifest_edit`: `set(text, section, name, constraint)`, `remove(text, section, name)` and `has(...)` edit `hecate.project.lua` as text (one line, everything else byte for byte, CRLF kept), refuse with the line to write by hand when the shape is not understood, and verify their result by evaluating it.
- `cli.manifest`: `parse(source, path?, limits?)` and `validate(table, path?)` for `hecate.project.lua` (sandboxed, schema-validated, `ConfigurationError` with pointers); `manifest.schema`.
- `cli.installer`: `install(options)` joins the manifest, LuaRocks, the lockfile and the checksums (injected file system and LuaRocks); `hecate install` writes `hecate.lock`, `hecate install --frozen` stops when it is missing or out of date and verifies the installed files afterwards.
- `cli.lockfile`: `parse`, `validate`, `serialize` (sorted, deterministic) and `outdated(lock, manifest)` (missing, orphan, wrongly flagged rocks, locked versions that break a constraint) for `hecate.lock`.
- `cli.digest`: `sha256(data)`, `sha256_file(path)`, `backend_name`, `using(backend)` (ADR 0028; the `digest` rock behind one seam, no fallback for now).
- `cli.constraint`: `parse_version`, `compare`, `parse` and `satisfies` over the LuaRocks version and constraint syntax.
- `cli.luarocks`: `new(options)` (`config_text`, `environment`, `installed`, `outdated`, `install_dependencies`, `remove`, `pin`), `rockspec_text`, `rockspec_file_name`, `parse_lock`; the runner is injected.
- `cli.resolution`: `read_rockspec(name, text)`, `installed_files_digest(input)`, `build_lockfile(input)` (an installation to the records of `hecate.lock`) and `verify(lock, current)` (what `install --frozen` checks after installing).
- `cli.runner`: `run(program, args, options)`, suspending, over `reactor.run_process` (the real runner of `cli.luarocks`).
- `cli.commands.contract`: `hecate contract lint <file>` (exit 1 on an error finding), `hecate contract diff <old> <new>` or `hecate contract diff <ref> [--file=<path>]` (the contract committed at a git ref, `git show <ref>:openapi.json`, against the application as it is now; exit 1 on a breaking change) over `openapi.lint` and `openapi.diff` of the project (run in the interpreter of the project, which needs `hecate install`), files of OpenAPI JSON, `--json`; and `hecate contract export [--output=<file>] [--pretty]`, the document of the application of the project (a child process loads `require(<module>).application(options)` with the `openapi` option from the `contract` section of the manifest, boots it and prints `Application:contract`).
- `cli.commands.doc` is `hecate doc build` (`--audience`, `--output`, `--yes`; reads the `doc` section of the manifest, asks before running LuaLS).
- `cli.serve`: `supervise(reactor, options)` (the child process of `hecate serve`: forwards `sigint`, `sigterm` and `sighup`, grace period then `sigkill`, restart on change, the exit code of the child, `128 + n` for a signal), `poll_changes`, `snapshot`; `cli.commands.serve` is the command (`--watch`, `--workers`).
- `cli.commands.run`: `hecate run <script> [-- <arguments>...]` runs a script of `scripts` in the manifest, or a `.lua` file of the project, in a child process with the project module path (the one of `serve`); `resolve`, `inside_project`.
- `cli.main`: `run(arguments, overrides?)` and `runtime(overrides?)`: what the process runs on (exact Lua release, LuaRocks, libuv, platform, current directory, the interpreter for the project) and the command line; `bin/hecate.lua` and the self-contained executable (OQ-13) both call it. `Runtime.lua_interpreter_arguments` puts the interpreter in interpreter mode (the executable: `--lua`). `Runtime.luarocks_program`/`luarocks_arguments` do the same for LuaRocks (the executable: itself with `--luarocks`, its embedded LuaRocks 3.13).
- Security and platform notes: `install --frozen` writes a rockspec that asks for `name == version` for every locked rock, then verifies the installed files and that no rock outside the lock was installed; `rocks_servers` must be `https://` (or `file://`); `generate systemd` refuses control characters and escapes `%`, spaces and `$`; `package --output` must end in `.tar.gz`/`.tgz` (`.zip` on Windows). On Windows `hecate serve` and `hecate run` do not forward Ctrl+C (the console gives it to the child too): the child has the grace period, then is killed, and its exit code is 1; the manifest of the executable asks for UTF-8 and long paths (also enable `LongPathsEnabled`).
- `--json` failures: standard output holds one document `{ "ok": false, "error": { "message", "code" } }` (a usage error adds `"usage": true` and a `hint`); answers made with `Context:emit` carry `"ok": true`.
- `hecate.cli.Command`: `name`, `summary`, `usage`, `options`, `run(context)`; `Context:emit(value, text)` prints JSON under `--json`.

## Layout (once implemented)

```text
src/hecate/cli/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
csrc/        native sources
```
