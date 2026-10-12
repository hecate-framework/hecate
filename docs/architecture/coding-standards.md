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

  The Phase 0 spike (OQ-3) confirms the exact idiom with Lua 5.5.1, LuaLS and the
  formatter, then updates this paragraph. Writing to a global is never allowed in
  library code.
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
- Every error class has a stable `code` (`hecate.http.HeaderTooLarge`) documented on the
  website.

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
- ASan + UBSan builds on Linux in CI; fuzzing targets for parsers (llhttp wrapper, JSON,
  BSON, protocol frame decoders) with libFuzzer.
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
