# Coding standards

Applies to every package, tool and example. Enforced by formatter, linter, LuaLS and
review agents.

## Language level

- Lua 5.5 (ADR 0001). Only the 5.5-only constructs listed in ADR 0001 are allowed.
- Library chunks define **no globals**. Lua 5.5 makes every free name a compile-time
  error once a `global` declaration is in scope; chunks therefore start by declaring,
  as constants, only the standard globals they read, for example:

  ```lua
  global <const> type, pairs, ipairs, error, setmetatable, string, table, math
  ```

  Confirmed with Lua 5.5.1 (OQ-3): after this declaration, reading any other free name
  is a compile-time error (`variable 'x' not declared`). LuaLS understands the
  construct; the repository has no formatter, so none needs to parse it. Writing to a
  global is never allowed in library code.
- Standard library functions used on hot paths are aliased to locals at the top of the
  chunk (`local type, pairs = type, pairs`).

## Layout of a package

```text
packages/<name>/
  README.md               scope, status, API summary, dependencies
  CLAUDE.md               agent context for this package
  hecate-<name>-scm-1.rockspec
  src/hecate/<name>/      Lua sources (init.lua is the public entry point)
  csrc/                   C sources, if any (C11)
  tests/unit/             fast tests, no network
  tests/integration/      tests needing I/O or services
  tests/fixtures/
  benchmarks/             package-level micro-benchmarks
  examples/               short runnable snippets used by the documentation
```

## Naming

- Glossary terms are mandatory (ADR 0004).
- `snake_case`: modules, files, functions, methods, fields, local variables.
- `PascalCase`: classes, interfaces, traits, enumerations.
- `UPPER_SNAKE_CASE`: constants.
- One public class per file; the file is the `snake_case` of the class
  (`user_repository.lua` → `UserRepository`).
- Booleans read as predicates: `is_closed`, `has_body`, `can_retry`.
- No abbreviations except standard ones (`uri`, `http`, `sql`, `json`, `id`, `tls`).
- **Spelling.** Prose and identifiers use British spelling (`finalise`, `normalise_config`,
  "licence", "behaviour", "catalogue"). External identifiers keep their own spelling: the
  rockspec field `license`, SPDX identifiers, badges and the task name `check-licenses`.
- **Operations name the verb first**, then the transport: `connect_tcp`, `listen_pipe`,
  `bind_udp`; the same name in `reactor` and in `net`.

## Modules

- A module returns exactly one value (a table or a class). No side effects at `require`
  time other than defining that value: no I/O, no registration, no global mutation.
- Public API is what `init.lua` exports and what the README lists. Anything else is
  internal (`hecate.<name>.internal.*`) and may change without notice.

## Errors

Decided in [ADR 0018](../adr/0018-error-signalling.md).

- **Programmer errors and exceptional failures raise** an instance of the
  `hecate.core.Error` hierarchy (`error(SomeError { ... }, level)`).
- **Expected absence** returns `nil` (e.g. `repository:find(id)` returns `nil` when not
  found). Never `nil, message` pairs in public APIs.
- Error messages: lower case first word, no trailing period, mention the offending value
  and the expected one: `invalid port 70000: expected an integer in [0, 65535]`.
- Every error class name ends with `Error` and has a stable `code`, the full class name
  (`hecate.http.FieldTooLargeError`), documented on the website.
- **Message prefix.** A message that is raised for a call starts with the qualified
  `module.function:` exactly as the caller wrote the call: `net.bind_udp: unknown option foo`,
  `json.decode: ...`, `reactor.spawn: ...`; for a constructor, the class:
  `net.BufferedReader: ...`; for a method, `Class.method`: `net.TcpStream.read: ...`. Failures of
  an operation reported by the operating system carry the prefix too
  (`net.TcpStream.read: ECONNRESET ...`, `reactor.connect_tcp: connect 127.0.0.1:80: ECONNREFUSED ...`); the stable
  `context.operation` stays as the data of the failure. The prefix is never bare (`resolve` exists in `reactor` and in
  `net`).
  The one exception is a message raised from inside the scheduler, in a computation that made no call
  the caller wrote: the cancellation signals delivered to a computation (`cancelled`, `future cancelled`,
  `scope cancelled`, `the scope body failed`, `a sibling computation failed`) and the report of a
  coroutine that called `coroutine.yield` directly (`a managed coroutine called coroutine.yield
  directly; ...`). This list is complete; every other message of `reactor` and `net` carries the prefix,
  including `reactor.deadline: deadline exceeded`, `reactor.run: deadlock: ...` and
  `reactor.Channel.send: the channel is closed`. A method of a class that another package wraps names the
  wrapper when it is reached through it (`net.TcpStream.write`, not `reactor.TcpStream.write`).

## Resources

- Anything holding an OS resource implements `__close` and is used with `<close>` in
  examples and internal code.

## Documentation in code

- Every public class, function, method and field carries LuaLS annotations
  (`---@class`, `---@param`, `---@return`, `---@field`, `---@async` for functions that
  may suspend).
- `---@async` is **mandatory** on every function that can suspend. A test checks that
  documented suspension matches behaviour (see testing.md).
- First line of a doc comment: one sentence in the indicative mood ("Returns ...").

### Annotations for the reference

The reference pages are generated from the LuaLS export (`lua-language-server --doc=<dir>
--doc_out_path=<output directory>`, JSON; owner decision of 2026-10-13: no annotation parser of
our own). Measured with LuaLS 3.19.1; the pitfalls below are why the convention exists.

1. **Every module table is a class.** The table a module returns carries `---@class
   hecate.<package>` (or `hecate.<package>.<submodule>`), with a `---` description above it.
   Functions on a plain, unannotated module table are absent from the export.
2. **Define a public function as `function M.name(...)` or `M.name = function(...)`** on the
   table of that class. A `local function` re-exported in a table constructor or by assignment
   loses its documentation (the export keeps a bare entry without parameters).
3. **Do not list functions in the table constructor** of the module (`local m = { f = x.f }`):
   LuaLS leaves constructor entries out of the export, and an entry hides a documented
   definition of the same name. Assign them afterwards (`m.f = x.f`).
4. **A module can be completed from several files.** `---@class hecate.reactor` may appear on the
   local table of `primitives.lua`, `dns.lua`, and so on: LuaLS merges classes of the same name,
   so `function M.sleep` there is documented as `hecate.reactor.sleep`. The description of the
   class comes from the `---` lines above one declaration; separate any `--` comment from a
   `---@class` line by a blank line, or it becomes the description. The public name must equal the
   name in the file (`reactor.sleep = primitives.sleep`); a function exported under another name
   is documented by a `---@field name fun(...): ...  description` line on the module class.
5. **Parameters and returns** use `---@param name type  description` and
   `---@return type name  description` (one line each; a continuation line is appended to the
   description of the whole function, so avoid it). The description survives in the export; a
   return without a name or a description is listed with `-`. For a `---@field`, only the first line
   of the description survives.
6. **First paragraph: one sentence of summary.** The paragraph is the page summary. Further
   paragraphs, separated by a `---` line, are details. A paragraph that starts with `Raises` feeds
   "Errors raised" (name error classes by their full name, ``hecate.core.ArgumentError``); a
   paragraph that starts with `Since` gives "Compatibility" the version that introduced the symbol
   (default: the version of the package). `---@see symbol` feeds "See also".
7. **`---@async` marks every function that can suspend.** It is exported (`async: true`) and shown
   as "May suspend". Unknown tags (`---@error`, `---@throws`, `---@since`, `---@version`) are
   dropped by LuaLS: do not rely on them.
8. **Private members** start with `_` or live in `hecate.<package>.internal.*`; the generator
   leaves both out.
9. **Examples** are tested files `packages/<package>/examples/<symbol>.lua` (for example
   `hecate.reactor.sleep.lua`); the generator includes the file in the page, and a test of the
   package runs it.

Generated pages: `lua tools/run.lua gen-reference` (needs `lua-language-server`).

## Formatting and linting

- Formatter: none for the Hecate repository until a formatter fully supports Lua 5.5
  (`global`, named varargs, prefix attributes); one is adopted then (owner decision,
  OQ-3, 2026-10-12). Style is kept by review and the linter: 2-space indentation,
  100 columns, double quotes. User projects choose their own formatter
  ([cli-and-packaging.md](cli-and-packaging.md#formatter-choice-proposed-oq-3)).
- Linter: luacheck if compatible, else the `tools/lint` rule set. Mandatory rules:
  no free names, no unused variables, no shadowing of upvalues, no `_`-member access
  from outside the class, `check-boundaries` rules.
- Type checking: LuaLS in CI (`lua-language-server --check`), zero warnings.

## C code

- C11, `-Wall -Wextra -Werror` (GCC/Clang), `/W4 /WX` (MSVC).
- ASan + UBSan builds on Linux in CI (`native.yml`, task `sanitize`); fuzzing targets for
  parsers (llhttp wrapper, JSON, BSON, protocol frame decoders) with libFuzzer (task `fuzz`:
  the cargo-fuzz targets of `net` and the C targets of `json`, `packages/json/csrc/fuzz`).
- No global mutable state; every native handle wrapped as userdata with `__gc` and
  `__close`.

## Performance

- No optimisation without a benchmark proving it; no hot-path change without running
  the relevant benchmark (see `benchmarks/`).
- Avoid closures and table allocation in per-request hot paths when a measured
  alternative exists.

## Commits and pull requests

- Conventional Commits scoped by package: `feat(router): ...`, `fix(postgresql): ...`,
  `docs(website): ...`, `chore(ci): ...`.
- One logical change per pull request; tests, docs and changelog in the same pull
  request.
