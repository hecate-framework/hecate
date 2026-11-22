<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `cli` v1: self-contained executable, `new`, `install`, `add`, `remove`, `update`, `serve [--watch]`, `test`, `doc`, `contract`, `toolchain`, `doctor`, `version` (docs/roadmap.md, Phase 3). Started on the owner's request of 2026-11-22.
- status: in-progress
- lock_until: 2026-11-22T16:30:59Z
- last_update: 2026-11-22T15:00:59Z

## Done

- Claimed the item (branch `claude/loving-shannon-flx2ar`, draft pull request #231).
- Step 1: parser, dispatcher (`hecate.cli.run`), `--help`, `--json`, exit codes, `version`; tests in `packages/cli/tests/unit`; typecheck, lint and gates green locally.
- Step 2: `packages/cli/bin/hecate.lua` entry point; shell completion (`completion <shell>`, hidden `__complete -- words`, `Command.hidden`); bash script checked by simulating `COMP_WORDS`. CI fix: `gen-catalogue` must be run after a README status change.
- Step 3: manifest `hecate.cli.manifest` (sandbox in `hecate.cli.internal.sandbox`, schema, tests in `manifest_test.lua`). CI green on the three platforms for steps 1 and 2.
- Step 4: lockfile format (`hecate.cli.lockfile`: parse, validate, serialize, outdated). Roadmap item added for the shared sandbox (owner, 2026-11-22).
- Step 5: `hecate.cli.digest` with the `digest` and `plc` backends; `plc 0.5-1` installed in `ci.yml` and `digest 0.0.1-1` installed in `ci.yml` (first push: watch that the three platforms install both) and in `tools/cloud/setup.sh`. The `digest` rock IS installable here: its archive URL is refused by the proxy, a `git clone --depth 1 --branch v0.0.1 https://github.com/osch/lua-digest spikes/OQ-13/lua-digest` is served; then `luarocks --tree .hecate/rocks make rockspecs/digest-0.0.1-1.rockspec`. CI finding: on Windows the `digest` build must run from pwsh (under bash the GNU `link` of Git shadows the MSVC linker: "link: unknown option -- d"); `ci.yml` has a separate pwsh step. Both backends pass the contract here and agree with `sha256sum` on a 16 MB file.

## Next steps

1. Read ADR 0009, 0010, 0028, 0029 and the OQ-13 spike (not yet read in full).
2. Verify the zsh, fish and PowerShell completion scripts on a real shell (PowerShell may drop the empty last word: the script appends `""`, check on CI; add a CI step or a test that runs them where the shell exists). `--version` alias.
3. LuaRocks constraint syntax (`~> 0.3`, `>=`, `<`, `==`) in a pure module, to make `lockfile.outdated` compare constraints. Later a toolchain download uses `sha256_file`.
4. Then, one step each: lockfile, LuaRocks orchestration, `new` and templates, `install/add/remove/update`, `serve`, `test`, `doc`, `contract`, `doctor`, `toolchain`; the native executable (OQ-13, ADR 0029) in its own steps.
5. Package README, CHANGELOG, roadmap sub-items as steps land.

## Decisions taken (and where they are recorded)

none yet

## Doubts and questions for the owner

none. Decided by the owner (2026-11-22): the manifest keeps only the specified keys (`lua` is the only toolchain setting); the sandbox becomes a shared module of `core`, in its own roadmap item (`hecate.cli.internal.sandbox` stays a temporary copy until then).

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
