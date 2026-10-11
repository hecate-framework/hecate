# Spike OQ-3: LuaLS and StyLua on Lua 5.5 syntax

Status: **complete (Linux only, tooling check)**. The owner adopted the recommendation
on 2026-10-11, keeping the formatter as a project choice.

## Question

Do LuaLS and StyLua parse the Lua 5.5-only constructs (`global` declarations, named
varargs `...name`, prefix attributes), and what is the fallback if one does not? (OQ-3)

## Method

Both tools were built from source inside `spikes/OQ-3/` (git-ignored) on Linux x86_64
(cloud session). GitHub release downloads are blocked by the cloud network policy
(`github.com/*/releases` returns 403), so:

- StyLua 2.6.0 from crates.io: `cargo install stylua --version 2.6.0 --features lua54
  --root spikes/OQ-3/stylua` (the crate has no Lua 5.5 feature; `lua54` is the newest).
- LuaLS at commit `66d6405` (2026-09-22): `git clone`, submodules `3rd/luamake`,
  `3rd/bee.lua`, `3rd/lpeglabel`, `3rd/EmmyLuaCodeStyle`, then `./make.sh`. The build
  succeeded and the project's own test suite ran to completion. Checks used
  `lua-language-server --check` with `"runtime.version": "Lua 5.5"`.

macOS and Windows were not exercised: no workflow was added, since the Linux result is
already conclusive for StyLua and the LuaLS parser is portable Lua.

## Findings

| Construct | StyLua 2.6.0 (`--syntax lua54` and `all`) | LuaLS (`Lua 5.5`) |
|---|---|---|
| `local x <const>`, `<close>` (5.4 suffix form) | parses and formats | OK |
| `local <const> x` (5.5 prefix form) | **parse error** | OK (changelog: prefix attributes supported) |
| `global x`, `global function f()` | **parse error** | OK; undeclared names reported as `variable-not-declared` |
| `global <const> *` | **parse error** | OK |
| named varargs `function f(...args)` | **parse error** | OK; `args.n` accepted |
| read-only `for` control variable | parses (no syntax change) | `set-const` reported on assignment |
| plain Lua code | formats | OK |

Other LuaLS observations on a sample using all constructs:

- `global function bump()` triggers `lowercase-global`, a false positive for explicitly
  declared globals; disable that diagnostic or name globals accordingly.
- Declared-global strictness comes for free: `variable-not-declared` replaces the
  need for a custom `_ENV` guard at lint time.
- The bundled Lua 5.5 meta files, when scanned as part of a workspace, produce
  `duplicate-doc-field` noise; keep `metapath` outside the workspace.

## Interim formatter: EmmyLuaCodeStyle

LuaLS has no formatting command-line option; its formatter is the bundled
EmmyLuaCodeStyle (`3rd/EmmyLuaCodeStyle`, C++). Its standalone `CodeFormat` executable
was built with CMake (`nlohmann_json` submodule only) and run as
`CodeFormat format -f file.lua -d -o out.lua`.

| Construct | EmmyLuaCodeStyle `CodeFormat` |
|---|---|
| plain code, `for` loops, `local x <const>`, `local x <close>` | formats |
| named varargs `...t` | formats (accepted leniently) |
| `global x = 1`, `global x` | accepted but **misparsed** as an expression: spacing left untouched (`global   x`), no error |
| `global function f() end`, `local <const> x` (prefix form) | **syntax error**, file not formatted |

So it covers the subset allowed in the recommendation below, but it silently does not
format `global` declarations. It is less opinionated than StyLua and is maintained
separately from LuaLS, so it is a stopgap, not a replacement.

## Recommendation

1. **LuaLS**: adopt it as type checker and linter for Lua 5.5 as is. Pin a release or
   commit, and run it through a `tools/` task (`--check`, JSON output).
2. **Formatter**: the owner may choose between (a) no formatter until StyLua supports
   Lua 5.5, with the style enforced by review and LuaLS, or (b) EmmyLuaCodeStyle as an
   interim formatter for the allowed subset (see above). Either way StyLua is not
   needed now and is re-evaluated on each release. With (b) the ban below is still needed for `global` declarations and prefix attributes.
   **StyLua**: it cannot parse `global`, `...name` or prefix attributes, and a file it
   cannot parse is not formatted at all. Until upstream adds Lua 5.5, **ban those
   constructs in committed source** (ADR 0001 already lists mechanical lowerings:
   `local args = table.pack(...)`; strictness via LuaLS and the test-time `_ENV`
   guard) and use only the suffix attribute form `local x <const>`. Enforce the ban
   with a lint task (a grep on `^%s*global%s`, `%.%.%.%a`, `local%s*<`).
3. Re-test StyLua on each release; once it parses 5.5, lift the ban for the constructs
   ADR 0001 allows. Optional: open an upstream issue/PR (needs the owner's go-ahead).
4. If option (a) is chosen, the construct ban is no longer needed for formatting and
   can be dropped; LuaLS parses all of them. Other formatters were not evaluated.

The limitations of EmmyLuaCodeStyle are surfaced to project authors as a warning when
they select it: see
[cli-and-packaging.md](../architecture/cli-and-packaging.md#formatter-choice-proposed-oq-3).

## Remaining risks

- StyLua binaries cannot be downloaded in cloud sessions; CI and the bootstrap must
  use `cargo install` or an allowed mirror, or the allowlist must gain
  `github.com/JohnnyMorganz/StyLua/releases` (domain needed: `github.com`
  release assets and `objects.githubusercontent.com`).
- LuaLS has no prebuilt binary in cloud sessions either; building takes ~5 min with
  `ninja`, a C++17 compiler and the four submodules.
- Not verified on macOS and Windows.
