<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `cli` v1: self-contained executable, `new`, `install`, `add`, `remove`, `update`, `serve [--watch]`, `test`, `doc`, `contract`, `toolchain`, `doctor`, `version` (docs/roadmap.md, Phase 3). Started on the owner's request of 2026-11-22.
- status: in-progress
- lock_until: 2026-11-22T17:33:32Z
- last_update: 2026-11-22T16:03:32Z

## Done

- Claimed the item (branch `claude/loving-shannon-flx2ar`, draft pull request #231).
- Step 1: parser, dispatcher (`hecate.cli.run`), `--help`, `--json`, exit codes, `version`; tests in `packages/cli/tests/unit`; typecheck, lint and gates green locally.
- Step 2: `packages/cli/bin/hecate.lua` entry point; shell completion (`completion <shell>`, hidden `__complete -- words`, `Command.hidden`); bash script checked by simulating `COMP_WORDS`. CI fix: `gen-catalogue` must be run after a README status change.
- Step 3: manifest `hecate.cli.manifest` (sandbox in `hecate.cli.internal.sandbox`, schema, tests in `manifest_test.lua`). CI green on the three platforms for steps 1 and 2.
- Step 4: lockfile format (`hecate.cli.lockfile`: parse, validate, serialize, outdated). Roadmap item added for the shared sandbox (owner, 2026-11-22).
- Step 5: `hecate.cli.digest` with the `digest` and `plc` backends; `plc 0.5-1` installed in `ci.yml` and `digest 0.0.1-1` installed in `ci.yml` (first push: watch that the three platforms install both) and in `tools/cloud/setup.sh`. The `digest` rock IS installable here: its archive URL is refused by the proxy, a `git clone --depth 1 --branch v0.0.1 https://github.com/osch/lua-digest spikes/OQ-13/lua-digest` is served; then `luarocks --tree .hecate/rocks make rockspecs/digest-0.0.1-1.rockspec`. CI finding: on Windows the `digest` build must run from pwsh (under bash the GNU `link` of Git shadows the MSVC linker: "link: unknown option -- d"); `ci.yml` has a separate pwsh step. Both backends pass the contract here and agree with `sha256sum` on a 16 MB file.
- Step 6: `hecate.cli.constraint` (port of LuaRocks version and constraint rules; 225-pair differential test against `luarocks.core.vers` passes with `LUA_PATH=/opt/lua-5.5/share/lua/5.5/?.lua;;`), constraints validated in the manifest, checked by `lockfile.outdated`. CI green on the three platforms for steps 1 to 5.
- Step 7: `hecate.cli.luarocks` (isolated config, install, installed-set check, pin, `parse_lock`, rockspec generation). Smoke-tested against the real LuaRocks 3.13 in a scratch tree (install, list --porcelain, pin, parse): works; finding: the rockspec file must be named `<name>-<version>-1.rockspec`.
- Step 8: `hecate.cli.resolution` (rockspec facts, `build_lockfile`); read on the real rockspecs of `plc` and `digest`.
- Step 9: `reactor.run_process` takes `env` and `cwd` (owner go-ahead, 2026-11-22; tests in `packages/reactor/tests/integration/process_test.lua`); `hecate.cli.runner` is the real runner. Watch the three CI platforms for the quoting of `-e` arguments in the new reactor tests.

## Next steps

1. Read ADR 0009, 0010, 0028, 0029 and the OQ-13 spike (not yet read in full).
2. Verify the zsh, fish and PowerShell completion scripts on a real shell (PowerShell may drop the empty last word: the script appends `""`, check on CI; add a CI step or a test that runs them where the shell exists). `--version` alias.
3. The `hecate install [--frozen]` command that joins the pieces: read the manifest and `hecate.lock`; `--frozen` stops at `lockfile.outdated`; otherwise write `.hecate/luarocks/config.lua`, the generated rockspec (`rockspec_file_name`) and run `install_dependencies` and `pin`; read `luarocks.lock` (`parse_lock`), the installed rockspecs under `<tree>/lib/luarocks/rocks-5.5/<name>/<version>/` (the layout differs per Lua version: ask `luarocks` for it rather than hard-code it) and call `resolution.build_lockfile`; write `hecate.lock`. The real runner is `hecate.cli.runner.run`. Then `add`, `remove`, `update`, `outdated`.
4. Then, one step each: lockfile, LuaRocks orchestration, `new` and templates, `install/add/remove/update`, `serve`, `test`, `doc`, `contract`, `doctor`, `toolchain`; the native executable (OQ-13, ADR 0029) in its own steps.
5. Package README, CHANGELOG, roadmap sub-items as steps land.

## Decisions taken (and where they are recorded)

none yet

## Doubts and questions for the owner

- **What `sha256` of a lock record covers** (owner asked, 2026-11-22: "isn't there already a sha verification in luarocks?"). Checked in the LuaRocks 3.13 sources: LuaRocks verifies only `source.md5` when a rockspec declares it (`fetch.lua`), an optional MD5 that neither `plc` nor `digest` declare (their sources are a `git://` URL and a GitHub zip); there is no general SHA check, and the rockspec itself is unsigned. Downloading the archives ourselves is not realistic (an HTTP client, the layout of the servers, and git sources have no archive to hash). A realistic and useful option: hash the **installed files** of a rock (the list is in its `rock_manifest`, where LuaRocks keeps an MD5 per file) into one SHA-256 (sorted path and file hash), recorded at the first resolution and checked by `install --frozen` on every later machine: it detects an upstream that changed after locking (a moved tag, a replaced zip) for pure-Lua rocks; for `native` rocks the files differ per platform, so they keep the rockspec checksum. The first resolution still trusts what the server delivers (trust on first use, as for npm integrity). Implemented meanwhile: the SHA-256 of the installed rockspec only. Please decide: keep the rockspec checksum, or add the installed-files hash.
- Already decided by the owner (2026-11-22): the manifest keeps only the specified keys (`lua` is the only toolchain setting); the sandbox becomes a shared module of `core`, in its own roadmap item (`hecate.cli.internal.sandbox` stays a temporary copy until then).

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
