# Spike OQ-13: the `hecate` executable

Status: **partial (Linux x86_64 only, time-boxed)**. Recommendation only; the owner decides. macOS and Windows
were not built; what is said of them is an assessment, marked as such.

Scope note (owner correction on pull request #200): a first iteration embedded the framework packages and
their native modules in the binary. That answered the wrong question and was dropped. The binary carries only
what the CLI commands need; the framework packages and their native modules reach a project as LuaRocks
dependencies, installed by `hecate install` (ADR 0009).

## Question

The user flow: download the binary; `hecate new` (or clone a project); `hecate install` (LuaRocks wrapper);
`hecate serve`. Then: **what must the binary contain, and should the Lua interpreter that runs the CLI be
embedded in it or downloaded with the toolchain?**

## Method

Throwaway prototype in `spikes/OQ-13/` (git-ignored); sources kept in [`OQ-13/`](OQ-13/): `cli.lua`,
`cli_main.c`, `serve_luv.lua`. GCC 13, Lua 5.5.1, LuaRocks 3.13, luv 1.53.0 built as a static library.

1. **Toolchain in a user directory.** `/opt/lua-5.5` (Lua, headers, LuaRocks) copied to
   `home/toolchains/lua-5.5.1`, as `~/.hecate/toolchains/lua-5.5.1` would be.
2. **CLI host**: 40 lines of C that run an embedded Lua bytecode chunk (`cli.lua`, standard library only):
   `install` runs the toolchain's LuaRocks against a project tree and a local `file://` rock repository, `serve`
   runs the project script with the toolchain's `lua`. Nothing from `packages/` is inside.
3. The same host with luv linked in (to measure the cost of process control), and a `serve` written with
   `uv.spawn` and `uv.new_signal`.

## Findings

| Check | Result |
|---|---|
| CLI host with only the Lua standard library | **285 KB** stripped, 4 shared objects (libc, libm, libdl) |
| Same host plus luv (process, signals, file system, network) | 674 KB stripped, **+390 KB** |
| Flow with an empty environment: `hecate install` then `hecate serve` | works: the rock `dep-a` is installed into the project's `lua_modules` by the toolchain's LuaRocks, and the project script runs on the toolchain's `lua` and finds it |
| Toolchain size (Lua, headers, LuaRocks) | 2.8 MB on disk, **825 KB** as `.tar.gz` |
| Is a stock toolchain relocatable? | **No.** `bin/luarocks` and `etc/luarocks/config-5.5.lua` hard-code the install prefix (`/opt/lua-5.5`), and the `lua` binary has the usual `/usr/local` defaults. A copy elsewhere fails. Rewriting the prefix in the two files (a `sed` at install time) was enough: the relocated LuaRocks installed the rock. So a prebuilt toolchain archive can be unpacked anywhere if the CLI writes the prefix, or if the toolchain is built at its final path |
| Plain Lua as the only process API (`os.execute`, `io.popen`) | `serve` leaks: after `SIGTERM` to the CLI (a process manager, `docker stop`, CI cancel) the CLI exits and its child server **keeps running** (2 processes left). Lua has no `exec`, no signal handler and no portable child control |
| `serve` with luv (`uv.spawn`, a `sigterm` handler that kills the child) | child stopped cleanly, exit status and signal propagated, no process left |

## What the CLI binary needs (from the command list)

| Need | Commands | Source |
|---|---|---|
| Lua to evaluate the manifest in a sandbox, lock files, templates, `--json` output | all | the embedded interpreter, standard library only |
| Spawn and supervise child processes, forward signals, exit codes | `install`, `serve`, `test`, `doc`, `migrate`, `run` | a native layer: luv (+390 KB), or a smaller own C function (`exec` on Unix, `CreateProcess` plus a job object on Windows) |
| Download toolchains and rocks index, verify sha256, unpack archives | `toolchain install`, `new`, `self update` | not decided: shell out to `curl` and `tar` (Windows 10 and later ship both), or a native HTTPS client and archive reader (hecate's Rust TLS module is 2.8 MB, OQ-4) |
| Hashing (sha256) for `hecate.lock` | `install`, `add` | not in the Lua standard library: an existing rock fits (`plc`, pure Lua, or `hmac`, C; see the sha256 table), or an external tool |

Everything else the commands appear to need (`hecate.kernel`, `hecate.test`, `hecate.doc`, `hecate.openapi`,
`hecate.migration`, the schemas, the reactor) runs **inside the project's interpreter**, on the project's
rocks. The CLI starts that interpreter; it does not load those packages itself. This contradicts two texts, to
be settled by the owner: the `Depends on` row of `packages/cli/README.md` (lists `reactor`, `kernel`, `test`,
`doc`, `openapi`, `migration`, ...) and the wording of ADR 0010 (Accepted: "embedding Lua 5.5, the CLI modules
and the native modules it needs"). I did not edit either.

## Embed Lua in the binary, or download it with the toolchain?

The toolchain (Lua, headers, LuaRocks) is downloaded per project in every case: native rocks compile against
its headers and the project must run on its own interpreter. The question is only about the interpreter that
runs the CLI's own code.

| | Embedded interpreter | CLI as Lua code run by a downloaded interpreter |
|---|---|---|
| Bootstrap | nothing to fetch before `hecate version`, `doctor`, `new`, `toolchain install` | the first command needs a downloaded Lua, and a native launcher is needed anyway to fetch it |
| Size | +285 KB total (the interpreter is a part of it) | smaller launcher, but the CLI code ships as separate files that must be kept in sync with the launcher |
| Lua version | the CLI's Lua is independent of the project's (`lua = "5.5"` in the manifest); the CLI can move to a newer Lua without touching projects | the CLI would follow a toolchain version, or carry its own copy, which is an embedded interpreter again |
| Process control | native code is already in the binary | the same need, unchanged |
| Single file to install, sign, update | yes | no: a launcher plus data |

## Recommendation

1. **Embed the interpreter.** A host of about 40 lines of C plus the CLI modules as bytecode is 285 KB, needs no
   download to start, and keeps the CLI independent of the Lua version of any project. Downloading it saves
   nothing, because a native launcher is needed either way.
2. **Keep the native layer to what the CLI uses**: process control (spawn, `exec`, signal forwarding) is
   required by the `serve` result above; luv provides it for +390 KB and is already a project dependency, a
   smaller own function is the alternative. Hashing needs a native function or a tool.
3. **Decide download and unpacking separately**: shell out to `curl` and `tar` (nothing added to the binary,
   to be confirmed on the platforms), or a native client. Not decided here; the cost is TLS (2.8 MB).
4. **Toolchains**: publish prebuilt archives per platform (825 KB here), unpacked under
   `~/.hecate/toolchains/` with the prefix rewritten by the CLI, or build at the final path (needs a C compiler,
   absent on most Windows and macOS machines). The CLI must run LuaRocks through its own configuration, as the
   specification already says.
5. Signing and notarisation (macOS), Authenticode (Windows) apply to one small file per platform and need
   certificates only the owner holds: Apple Developer ID and a Windows signing certificate or service. Unsigned
   binaries from a download are quarantined (macOS) or warned about (Windows SmartScreen); Homebrew, Scoop and
   `curl | sh` installs avoid part of it.

## Open points

- macOS, Windows, arm64 and musl were not built; `curl` and `tar` availability and flags on the three platforms
  were not tested; a Windows toolchain needs the import library settings of OQ-2.
- A prebuilt Lua 5.5 toolchain archive per platform is a release artefact that does not exist yet.
- sha256 rocks were checked in isolation on Lua 5.5, not yet embedded in the CLI host or used on a lock file.
- Decisions for the owner: embedded interpreter or not; luv or own process function; how downloads are done;
  signing routes and whether unsigned binaries are acceptable for `0.1.0`; correct the `Depends on` row of
  `packages/cli/README.md` and the wording of ADR 0010.

## Owner answers (2026-11-14, pull request #200) and follow-up measurements

- The interpreter is embedded (adopted). Once Hecate supports Lua 5.4, a command switches the interpreter of a
  project, which downloads the interpreter that the binary does not carry (the toolchain archives above).
- Interpreters are shipped **compiled**: one archive per platform and architecture, each built by a CI job;
  building from sources stays the fallback for unsupported platforms. The embedded interpreter is compiled and
  linked by the release CI of each target.
- Native modules ship inside rocks as binary rocks (already verified, [OQ-41](OQ-41-rock-binaries.md));
  rock downloads are LuaRocks's job; the CLI does not download rocks itself.
- Unsigned binaries are acceptable for `0.1.0`; signed is better.
- Installers: Windows setup executable that installs the binary; Linux and macOS channel not chosen yet.
- sha256: use an existing rock if one fits. **First check (wrong conclusion, corrected below):** I tried `sha2`,
  `lsha2` and `lua-hashings-and-nums` only, concluded that none fitted, and had misused the API of the last one.
  Redone on 2026-11-14 with Lua 5.5.1: every candidate was installed in its own tree and checked against
  `sha256sum` on `abc` and on 16 MB of data, then timed.

  | Rock | Kind, licence | Lua 5.5 | Correct | Speed (16 MB) |
  |---|---|---|---|---|
  | `hmac` 0.4.1 | C, MIT | builds and loads | yes | **0.07 s** (about 220 MB/s) |
  | `plc` 0.5 | pure Lua, MIT | loads | yes | 6.1 s (about 2.6 MB/s) |
  | `lua-hashings-and-nums` 1.0.3 | pure Lua, MIT | loads | yes | about 50 s per MB: unusable |
  | `sha2` 0.2.0 | C, written for Lua 5.1 | does not compile (`luaL_openlib`, `luaL_reg`) | n/a | n/a |
  | `digest` 0.0.1 (osch) | C, one file, MIT AND BSD-3-Clause | built by hand from the raw sources (the rockspec downloads a GitHub archive, blocked here); compiles on 5.5 without warning | yes | **0.07 s**; also MD5, SHA-384/512, HMAC, streaming; its own suite: 1741 assertions pass, 1 check fails (it counts fixture files, I could fetch only some) |
  | `lua-resty-crypto` | LuaJIT `ffi` over OpenSSL, no licence declared | cannot run on PUC Lua 5.5 | n/a | n/a |
  | `lua-hashings` | not listed for Lua 5.5; its 5.5 successor is `lua-hashings-and-nums` | see above | n/a | n/a |
  | `lsha2` 0.1 | Lua for 5.1/5.2 with `bit32`, GPL-3 | not tried: licence | n/a | n/a |
  | `luagcrypt` | C binding of libgcrypt | needs the libgcrypt headers and library on the machine | not tried | not tried |
  
  `plc` is fast enough for the CLI (an 825 KB toolchain archive in about 0.3 s) and is embedded as Lua source, no
  native code to build on three platforms. `digest` and `hmac` are about 80 times faster and also give HMAC, but a
  C module must be linked into the embedded interpreter on every target; `hmac` also builds with three other rocks
  (`configh`, `lauxhlib`, `luarocks-build-hooks`), `digest` with none. The luarocks.org search for "sha" returns 50 rows, most of them
  noise (`shared`, `shape`, `shadow`); about ten are hash libraries.

### Second round of answers (2026-11-14)

- Shipping: like Node.js. A Windows setup executable, a macOS `.pkg` installer and Linux archives, with Homebrew,
  winget and Scoop on top. A `curl | sh` installer for Linux and macOS is not opposed (it avoids the macOS
  quarantine attribute); to be settled with the installers item.
- `lsha2`: `github.com` and `codeload.github.com` answer `403` from the cloud environment (network policy), but
  `raw.githubusercontent.com` and `luarocks.org` are reachable, so the rockspec and the sources were read
  (2026-11-14). Rejected on its own metadata: "SHA224/SHA256 in Lua 5.1/5.2", depends on the `bit32` rock, and
  licence **GPL-3**, which cannot be a dependency of an MIT project.
- sha256: a rock fits after all (see the table above); the vendored C implementation stays the fallback.
- Signing: issues [#201](https://github.com/hecate-framework/hecate/issues/201) (Apple Developer ID) and [#202](https://github.com/hecate-framework/hecate/issues/202) (Windows signing route) record the prerequisites.
- The CLI dependencies are corrected in this pull request: `Depends on` of `packages/cli/README.md`, the
  rockspec and the overview graph now list `core`, `reactor`, `log`, `json` and `schema` only (the confinement of
  luv to `reactor` makes `reactor` the way to supervise processes). ADR 0010 is unchanged: its wording ("the native
  modules it needs") already fits.

### Third round (2026-11-14)

- sha256: the owner leans towards `plc` and asks that switching to another rock (such as `hmac`) stays easy. A
  one-module seam, `digest`, with a backend per rock and a contract test run for both backends, is in
  [`OQ-13/`](OQ-13/) (`cli_digest.lua`, `digest_backend*.lua`, `digest_test.lua`; the `plc`, `hmac` and `digest` backends pass). The dependency
  is proposed in [ADR 0028](../adr/0028-cli-sha256-rock-behind-a-seam.md) (Proposed): a new third-party
  dependency needs the owner's acceptance, so no rockspec was changed.
- Fourth round: `digest`, `lua-hashings` and `lua-resty-crypto` (named by the owner) were checked. `digest` is the
  strongest C candidate: correct, as fast as `hmac`, one C file, no other rock; it is now a third backend of the
  seam. `lua-resty-crypto` needs LuaJIT's `ffi`; `lua-hashings` has no Lua 5.5 listing and `lua-hashings-and-nums`
  is its successor. The earlier note "`digest` not tried" was my omission, caused by the blocked GitHub archive,
  which I worked around with the raw files.
- Fifth round (owner: "we might as well want `digest` instead of the other rocks"): `digest` becomes the proposed
  choice, `plc` the pure-Lua fallback. Facts behind it, read on 2026-11-14: published 24 days earlier, 215
  downloads on the module page, one maintainer, used as a dependency by one other rock. It continues `lua-sha2`
  (itself the revival of the 2010 `sha2` binding of Cosmin Apreutesei, the lineage of the old `sha2` rock that does
  not compile on Lua 5.5), with the hash cores of Gifford (`sha2.c`, BSD-3-Clause) and of the Kepler Project
  (`md5.c`, MIT). Its README claims CI on Lua 5.1 to 5.5 and LuaJIT on Linux, and Lua 5.5 on macOS and on Windows
  (MSVC and MinGW): the author's claim, not checked here. "Best one out there" is not established: only the
  candidates found by the searches above were tested. Risks recorded in ADR 0028: a young single-maintainer
  project (mitigated by the seam, and by vendoring the single C file with its two cores as yyjson is), and no
  compilation on macOS or MSVC by us yet (to be checked in a throwaway workflow before the ADR is accepted).
- Sixth round (owner, 2026-11-14): ADR 0028 accepted (`digest`, `plc` as fallback); signing is left for the owner to
  handle later (issues #201 and #202 stay open).

### Three-platform check of `digest` (2026-11-14)

A throwaway workflow (`spike-oq13-digest`, in the history of pull request #200 at commit `45ed610`, removed after
the run) installed `digest` and `plc` with `luarocks install` on Lua 5.5.1 built by the repository's bootstrap, ran the
rock's own suite from a clone of its `v0.0.1` tag (all fixtures present), then the contract test of the seam for the
`digest` and `plc` backends, then hashed 16 MB.

| Runner | `luarocks install digest` | Rock's own suite | Contract test (both backends) |
|---|---|---|---|
| ubuntu-latest (x86_64) | built | passed | passed |
| macos-latest (arm64) | built | passed | passed |
| windows-latest (MSVC 14.51) | built | 2948 + 806 assertions, 0 failed | passed |
| ubuntu-24.04-arm (aarch64) | built | passed | passed |
| macos-15-intel (x86_64) | built | passed | passed |

- Windows, 16 MB: `digest` 0.055 s, `plc` 6.76 s, identical hash (`a06c26cb...`).
- The first Windows run failed in the workflow, not in `digest`: under Git's bash, GNU `link` shadows MSVC's
  `link.exe` (`link: unknown option -- d`); building the rock from PowerShell fixed it. Anything that builds a C rock
  on Windows must not run under Git's bash (the repository's bootstrap already avoids it).
- Earlier doubt resolved: the single failed check of the partial local run (fixtures not fetched) passes with the full
  fixtures. Not covered: Windows arm64, musl, the embedded build into the CLI host (not written yet), and the
  stricter release toolchains (code signing, minimum macOS version).

### Seventh round (owner questions, 2026-11-14)

- **What has to be downloaded?** Rocks all go through LuaRocks. What LuaRocks cannot fetch is its own interpreter:
  ADR 0010 has the CLI install a *toolchain* per project (Lua, LuaRocks and headers), and `hecate self update` fetches
  the executable itself. That is all, and only the toolchain depends on the open choice (`curl` and `tar`, or a
  native client).
- **A possible alternative, not in ADR 0010:** the executable embeds Lua 5.5, so it could also be the interpreter of
  a Lua 5.5 project and run LuaRocks (pure Lua) itself, which would remove every download for the default Lua. Two
  Linux checks (`lua_host.c` in [`OQ-13/`](OQ-13/), linked with the Lua API exported): the host loaded a native rock
  built separately (`digest.so`), and it ran LuaRocks 3.13 and installed a binary rock into a tree. Not checked:
  Windows (native rocks link against `lua55.dll`, so the executable would have to export the Lua API under that
  name), macOS, building a source rock (needs the headers and a compiler), the embedded copy of LuaRocks, and Lua
  5.4 (a downloaded toolchain would still be needed). The choice between the two designs is the owner's.
- **"Supervises processes" meant this:** the CLI starts the project's interpreter for `install`, `serve`, `test`, `doc`,
  `migrate` and `run`, and must forward signals (Ctrl-C, `SIGTERM` from a container runtime), return the exit code,
  and, for `serve --watch`, restart it when files change. The worker processes of multi-process serving are
  supervised by `kernel`, not by the CLI (ADR 0023). On Unix the CLI could replace itself by the interpreter
  (`exec`) for everything but `--watch`; Windows has no `exec`.
- **OQ-45 and the hashing primitives:** the DBMS stores the password hashed, but a driver must still compute the
  *login proof*: PostgreSQL SCRAM-SHA-256 needs PBKDF2 with HMAC-SHA-256 over the password and a salt sent by the
  server, MySQL `caching_sha2_password` a SHA-256 scramble with the server's nonce, legacy PostgreSQL an MD5 of the
  password, the user and a salt. The password itself is not sent. `digest` (SHA-256, HMAC, MD5) covers all but
  PBKDF2, which is a loop over HMAC; this is a possible option for OQ-45, not decided here.

### Eighth round (owner answers, 2026-11-14)

- Toolchain: "Lua and LuaRocks binaries included in the binary too": the executable is the interpreter and `luarocks` of
  a Lua 5.5 project. Recorded as OQ-131 (resolved, issue [#205](https://github.com/hecate-framework/hecate/issues/205))
  and [ADR 0029](../adr/0029-executable-is-the-lua-5.5-interpreter.md) (Proposed; Windows, macOS and source-rock
  builds to verify before acceptance). A risk noted there: native rocks built against the official `lua55.dll` would
  not load in an executable that does not provide that interface.
- Managing running instances in production is the open question the owner sees, not the signal handling: OQ-133
  (issue [#207](https://github.com/hecate-framework/hecate/issues/207)); the mechanics of running the project's
  interpreter are OQ-132 (issue [#206](https://github.com/hecate-framework/hecate/issues/206)).
- OQ-45: the owner's direction is that `digest` serves the CLI only and that security cryptography belongs to the
  `security` package over `luasodium`, with argon2id by default; recorded in the OQ-45 entry. `luasodium` and
  `argon2` rocks exist on luarocks.org (correction in the ninth round: `luasodium` is at 2.4.1-2, not 0.0.11-1); neither was installed or tested here.

### Ninth round (owner answers, 2026-11-14)

- ADR 0029: the owner accepts it once it is verified on all platforms, which is the purpose of this spike. The
  verification is a throwaway workflow (`spike-oq13-interpreter`, scripts `verify_interpreter.sh` and
  `verify_interpreter.ps1` in [`OQ-13/`](OQ-13/)); its result is recorded below.
- libsodium, checked with its headers (1.0.18, Ubuntu 24.04) and a C test: SHA-256, SHA-512, HMAC-SHA-256/512,
  argon2id and scrypt are there, and its HMAC-SHA-256 matches OpenSSL's; **PBKDF2, MD5 and SHA-1 are absent**.
  `luasodium` is at 2.4.1-2 (about 31,700 downloads, MIT; I wrote 0.0.11-1 earlier, which was only an old version
  in a listing); its source tarball is on `buffering.party`, blocked in the cloud environment, so it was not built
  on Lua 5.5. The consequences for the database login methods are in the OQ-45 entry.
- Supply chain: LuaRocks.org published a security incident report (September 2026): a remote code execution on the
  server, exploited between 9 July and 20 August 2026, fixed on 26 September, no evidence found of modified existing
  packages, three attacker-uploaded packages removed, and a recommendation to use LuaRocks 3.12 or newer. The bootstrap
  and the embedded LuaRocks are 3.13.0; the checksums of `hecate.lock` are the mitigation for rocks fetched later.
  I read the report page only, not the details of what was checked.
- OQ-133: the `kernel` already implements the graceful stop (`sigint`, `sigterm`) and, on Unix, the rolling reload of
  ADR 0023 on `sighup` in a primary (`Supervisor:reload`; I first wrote that the trigger was missing, which was wrong); the
  open parts are reload on Windows, the upgrade of the primary or of the binary (out of scope in ADR 0023) and
  whether the CLI adds commands. Recorded in the OQ-133 entry.

### Verification of ADR 0029 (2026-11-14)

A throwaway workflow (`spike-oq13-interpreter`, in the history of pull request #200 up to commit `8675396`, removed after the
run) ran `verify_interpreter.sh` or `verify_interpreter.ps1` on each platform: a host program embedding Lua 5.5 with the Lua
API exported (Windows: linked to `lua55.dll`) (1) loads a native rock built by the standard toolchain, (2) runs the LuaRocks
3.13.0 sources and installs a pure-Lua rock, (3) runs LuaRocks to build a source rock with a C module from the Lua headers
and loads it, (4) runs the sha256 contract test with the `digest` and `plc` backends.

| Runner | Result |
|---|---|
| ubuntu-latest (x86_64) | all four checks pass |
| ubuntu-24.04-arm (aarch64) | all four checks pass |
| macos-latest (arm64) | all four checks pass |
| macos-15-intel (x86_64) | all four checks pass |
| windows-latest (MSVC, x86_64) | all four checks pass **with `lfs` available to the host**; checks 1 and 2 passed without it, check 3 failed |

- The Windows failure, found from the verbose output of LuaRocks: without LuaFileSystem it lists the files of an installed rock with
  the `find` command, which on Windows is the text-search tool; the list is empty, the rock manifest is empty, nothing is deployed,
  and the rock reports "installed" yet cannot be required. Installing `luafilesystem` with the standard toolchain and giving the
  host access to it fixed it. The official `luarocks.exe` bundles `lfs`.
- Windows needs `lua55.dll` beside the executable: native rocks link against it, and the host shares it.
- Not verified: Windows arm64, musl, Lua 5.4, embedding the LuaRocks sources and the Lua headers in the executable, and the
  installers. ADR 0029 is Accepted on these results.

### luasodium on Lua 5.5 (2026-11-14, tarball supplied by the owner)

The owner supplied the source tarball of `luasodium` 2.4.1 (sha256 `7f7e61fff2c8cf30d4e8248cee482c9b2028ac5cbeebe78341ef1ecb95914b02`)
because its host, `buffering.party`, is blocked in the cloud environment. It was treated as untrusted: the file list was read first
(255 entries, all under one directory, no absolute or `..` paths, no links), then it was built through LuaRocks from its own rockspec
with the source URL pointing at the local file, in a git-ignored directory (`spikes/OQ-45/`).

- It builds on Lua 5.5.1 against libsodium 1.0.18 (Ubuntu 24.04), with only libsodium's own deprecation warnings.
- SHA-256 (16 MB in 0.064 s) and HMAC-SHA-256 match `sha256sum` and OpenSSL; argon2id is the default password hash and
  `crypto_pwhash_str` and `crypto_pwhash_str_verify` work (`$argon2id$v=19$m=65536,t=2,p=1$...`).
- Its HMAC functions take a fixed 32-byte key and have no streaming form; there is no PBKDF2, MD5, SHA-1 or HKDF.
- PBKDF2-HMAC-SHA-256 over `crypto_hash_sha256` alone (RFC 2104 HMAC, any key length) matches OpenSSL on two vectors (the
  `password`/`salt`/4096 vector; a 100-byte password with 40 bytes of output) and takes 14 ms for 4096 iterations, the PostgreSQL
  SCRAM default. So SCRAM-SHA-256 needs nothing but `luasodium`.
- Not checked: Windows and macOS builds of `luasodium` (it needs the libsodium library on each), and its FFI bindings (LuaJIT only).

