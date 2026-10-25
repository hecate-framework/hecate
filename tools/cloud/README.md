# Claude Code cloud environment

Configuration of the cloud environment used by Claude Code cloud sessions
(claude.ai/code, `claude --cloud`, mobile app). Background:
[docs/architecture/ai-assisted-development.md](../../docs/architecture/ai-assisted-development.md#claude-code-in-the-cloud).

Create the environment from the environment selector at claude.ai/code (cloud icon above
the message box → Add cloud environment).

| Field | Value |
|---|---|
| Name | `hecate` |
| Network access | **Custom**, with "Also include default list of common package managers" checked |
| Allowed domains | see below |
| Environment variables | see below |
| Setup script | content of [`setup.sh`](setup.sh) |

## Allowed domains

```text
www.lua.org
lua.org
luarocks.org
*.luarocks.org
luarocks.github.io
dist.libuv.org
www.sqlite.org
sqlite.org
```

GitHub, the Docker registries, Ubuntu archives and the npm/PyPI registries are already in
the default list. Add a domain here when a spike or a task needs it, in the same pull
request that needs it.

## Environment variables

```text
BASH_DEFAULT_TIMEOUT_MS=300000
BASH_MAX_TIMEOUT_MS=1200000
```

Builds of native modules and full test runs exceed the 2-minute default command timeout.
`hecate.json` has no pure-Lua fallback (OQ-53): run `lua tools/run.lua build-native json` (and `build-native doc` for
the tests of `doc`) before the tests of `json` and of every package that depends on it.
Do not put secrets here: anyone who can use the environment can read its variables.

## Limits to keep in mind

- The VM is Ubuntu 24.04 x86_64 only. macOS and Windows are tested through GitHub
  Actions (`ci.yml`); a session pushes its branch, opens a pull request and follows the
  CI results (Auto-fix).
- About 4 vCPUs, 16 GB RAM, 30 GB disk per session.
- The GitHub proxy refuses tag pushes and branch deletions; branch protection on `main`
  prevents direct pushes.
