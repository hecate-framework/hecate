# Spike OQ-13: standalone `hecate` executable

Status: **partial (Linux x86_64 only, time-boxed)**. Recommendation only; the owner decides. macOS and
Windows were not built (no runner in this session); what is said of them is an assessment, marked as such.

## Question

ADR 0010: one executable per platform embedding Lua 5.5, the CLI modules and the native modules. Is it
feasible with the pieces Hecate already has (C modules, Rust `mlua` modules, luv), and what do code
signing and the six targets cost?

## Method

Throwaway prototype under `spikes/OQ-13/` (git-ignored); the three small sources are kept in
[`OQ-13/`](OQ-13/): `gen.lua`, `main.c`, `preload.c`. GCC 13, Lua 5.5.1 (`liblua.a`), Rust 1.97.

1. luv 1.53.0 (with its bundled libuv) built as a **static library** against the system Lua 5.5:
   `cmake -DWITH_LUA_ENGINE=Lua -DBUILD_MODULE=OFF -DBUILD_STATIC_LIBS=ON -DWITH_SHARED_LIBUV=OFF -DLUA_BUILD_TYPE=System ...`
   Builds unmodified.
2. `gen.lua` compiles every `.lua` file of `core`, `reactor`, `log`, `json`, `schema`, `router`, `container`
   and `config` (88 files) to stripped bytecode (`string.dump(f, true)`) into a C array table.
3. `main.c` is the host: `luaL_newstate`, `luaL_openlibs`, luv registered with `luaL_requiref`, an extra
   `package.searchers` entry that loads the embedded bytecode, then runs a script (`arg[1]`).
4. `preload.c` registers the native modules in `package.preload`:
   - `hecate.json.native`: the C module (`packages/json/csrc/native.c` + vendored yyjson) compiled into the host.
   - `hecate.json.encoder_native`: the Rust `mlua` module, rebuilt from a copy of `packages/json/native` with
     `crate-type = ["staticlib"]` (the `module` feature leaves the Lua symbols to the host), linked in.

## Findings

| Check | Result |
|---|---|
| Script run with `env -i`, no Lua installed, from an empty directory: luv timer, `hecate.json` encode (C and Rust natives), `require("hecate.core")`, `require("hecate.reactor")` | **works**, all in one process |
| Dynamic build (libc, libm only; `ldd` lists 5 entries) | 3.5 MB; 1.7 MB stripped; starts in about 2 ms |
| Fully static glibc build (`-static`) | links and runs, 4.9 MB, but the linker warns that `getaddrinfo` and `getpwuid` need the shared glibc at run time: a static glibc binary is not safe for DNS resolution. A musl target (`x86_64-unknown-linux-musl`) is the normal answer; not tried |
| Rust staticlib of an `mlua` module | **works**: the `luaopen_*` symbol is exported, 8.5 MB archive, 15 s build, no change to the source of the module; so `crate-type` must list `staticlib` next to `cdylib` for the embedded build |
| Error when a native module is missing | the packages already raise a clear `JsonError`; with `package.preload` the same code path serves the rock build and the embedded build, no change in the packages |
| Bytecode versus sources | bytecode is tied to the exact Lua build (5.5.1) and platform word size and endianness; fine for a binary that embeds its own Lua, but the build must generate it per target; sources can be embedded instead at a small start-up cost |

Not verified here, to be checked on the three-platform CI:

- **macOS**: static libuv and luv build there (luv is routinely built on macOS); Rust modules need
  `-undefined dynamic_lookup` only for dynamic modules (OQ-4 note), not for a staticlib. **Signing and
  notarisation** need an Apple Developer ID certificate (paid account), `codesign --options runtime` and
  `notarytool`; both are owner-held secrets, hence a release-pipeline step that is run by the owner's CI only.
  Unsigned binaries from a download are quarantined by Gatekeeper; installing through Homebrew or `curl | sh`
  (no quarantine attribute) works unsigned but is not a long-term answer.
- **Windows**: MSVC link of `liblua.lib`, luv and the Rust staticlib (`LUA_LIB`, `LUA_INC` as in OQ-4);
  needs `__declspec(dllexport)` only for dynamic modules. Authenticode signing needs a certificate (or Azure
  Trusted Signing); unsigned binaries trigger SmartScreen warnings, which hurts `winget` and Scoop adoption.
- **arm64** targets (macOS arm64, linux aarch64, Windows arm64): same code, native runners or cross builds.
  Windows arm64 runners and Rust `aarch64-pc-windows-msvc` availability were not checked.

## Options

| Option | Description | For | Against |
|---|---|---|---|
| A. Own host (this prototype) | about 60 lines of C, bytecode or sources embedded, natives in `package.preload` | no new dependency (ADR rule), full control, same modules as the rocks, trivial to add the three-platform build | we maintain the host and the embed generator |
| B. `luastatic`-like tools | generate such a host from Lua files | less code to write | third-party dependency (needs an ADR), designed for one script and rocks found on the system, not for several Rust and C natives |
| C. Ship Lua + a zip | the executable unpacks or finds a bundled interpreter and `.so` files | no embedding | not one executable; ADR 0010 asks for one; `.so`/`.dll` loading restrictions on signed macOS binaries (library validation) |

## Recommendation

Option A. It is the smallest design that meets ADR 0010 and reuses what is already proven by the
spike: the packages need no change; the only repository changes are in the build: `staticlib` next to `cdylib`
for each Rust module, a static `hecate-host` target, and an embed step in `tools/`. Treat musl as the
Linux target to settle (static, DNS-safe) and check macOS and Windows in a throwaway workflow before `cli` v1,
as was done for OQ-4. Code signing is a release-pipeline concern and needs certificates only the owner can
provide: Apple Developer ID and a Windows signing certificate or service. Decisions for the owner: which
signing route for each platform, and whether unsigned binaries are acceptable for the first `0.1.0` release.

## Open points

- musl build of luv, libuv and the Rust staticlib not tried.
- The CLI modules (`hecate.cli`) do not exist yet; the prototype embedded the Phase 0 to 2 packages.
- A native module with its own thread pool or `dlopen` use (SQLite, TLS) was not part of the prototype.
