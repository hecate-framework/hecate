<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `cli` v1: self-contained executable, `new`, `install`, `add`, `remove`, `update`, `serve [--watch]`, `test`, `doc`, `contract`, `toolchain`, `doctor`, `version` (docs/roadmap.md, Phase 3). Started on the owner's request of 2026-11-22.
- status: in-progress
- lock_until: 2026-11-22T19:59:25Z
- last_update: 2026-11-22T18:29:25Z

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
- Step 10: installed-files checksum (owner go-ahead, 2026-11-22): `installed_files_digest`, `checksum_of` in the lockfile, `verify`; checked on the real `plc` and `digest` trees (deployed files: `lua` is `<tree>/share/lua/5.5/`, `lib` is `<tree>/lib/lua/5.5/`, `bin` is `<tree>/bin/`; the rock directory is `<tree>/lib/luarocks/rocks-5.5/<name>/<version>/`).
- Step 11: `hecate.cli.installer` (`install` sequence over an injected file system and LuaRocks: config, generated rockspec, install, pin, read `luarocks.lock`, installed rockspecs and `rock_manifest` digests, `build_lockfile`; `--frozen` checks `outdated` before installing and `verify` after); tests in `installer_test.lua` with fakes. Run on a resumed session after PR #229 merged; this environment lacks `luv` and `digest` (the 3 local test failures are `digest_test`, `resolution_test` real-digest cases and `runner_test`; CI has them).
- Step 12: `hecate install [--frozen]` command (`commands/install.lua`, registered in `init.lua`; `execute(context, dependencies)` is injectable and tested in `install_command_test.lua`; `bin/hecate.lua` detects the LuaRocks version). Not yet run end to end against real LuaRocks and the network (watch CI; try `hecate install` in a scratch project with `plc`).
- Step (second session, 2026-11-22): fish and zsh completion scripts verified on real shells (`packages/cli/tests/unit/completion_shells_test.lua`, mutation-checked); PowerShell left to CI.
- Step (second session, 2026-11-22, 19:30Z): end-to-end run of `install` on a scratch project with the real LuaRocks and `plc`: found and fixed relative paths given to LuaRocks run from the work directory (absolute paths now, `Runtime.project_dir`) and the missing `.hecate/rocks` on the path of `bin/hecate.lua`. `install`, `install --frozen` and a tampered file (refused) behave as specified.

## Next steps

1. Read ADR 0009, 0010, 0028, 0029 and the OQ-13 spike (not yet read in full).
2. PowerShell completion: `completion_shells_test.lua` runs it where `pwsh` exists (Windows and Ubuntu runners); first run is CI: if the empty last word is dropped (the script appends `""`), fix `completion.lua`. fish and zsh pass locally (zsh with `compdef` and `compadd` stubbed, not through `compinit`). `--version` alias still open.
3. `add`, `remove`, `update`, `outdated` (manifest edit + install); a `cli-e2e` CI step on the three platforms that repeats the scratch-project run of `install` (it needs the network for luarocks.org, and `build-native json` for `--json`). Known gap: the lock records `lua = "5.5"` (from `_VERSION`), the specification wants the exact `5.5.1`: read it from `lua -v` or `luarocks config`.
4. Then, one step each: lockfile, LuaRocks orchestration, `new` and templates, `install/add/remove/update`, `serve`, `test`, `doc`, `contract`, `doctor`, `toolchain`; the native executable (OQ-13, ADR 0029) in its own steps.
5. Package README, CHANGELOG, roadmap sub-items as steps land.

## Decisions taken (and where they are recorded)

none yet

## Doubts and questions for the owner

- Already decided by the owner (2026-11-22): the manifest keeps only the specified keys (`lua` is the only toolchain setting); the sandbox becomes a shared module of `core`, in its own roadmap item (`hecate.cli.internal.sandbox` stays a temporary copy until then).

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
