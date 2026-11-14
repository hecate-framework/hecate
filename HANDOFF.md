<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Spike OQ-17 (split tool for the read-only mirrors: `splitsh-lite`, `git subtree split`, `git filter-repo`; determinism and speed), report to the owner before the mirrors item (owner decision of 2026-11-13).
- status: waiting-owner            <!-- in-progress | waiting-ci | waiting-owner -->
<!-- Optional, only when the owner holds this pull request for one run: - owner: session `<session id>`, why. -->
- lock_until: 2026-11-14T15:42:30Z
- last_update: 2026-11-14T15:42:30Z

## Done

- Claimed. Cloned splitsh-lite (36e0e74) and git-filter-repo (d7b75ac) under `spikes/OQ-17/`. `git subtree` is available (git 2.43).
- Installed `libgit2-dev` (1.7.2) by apt; splitsh-lite needs git2go v34, which accepts only libgit2 1.5.0 exactly. Cloned libgit2 v1.5.0 and configured it with cmake under `spikes/OQ-17/`.

## Next steps

1. Clone the three tools under spikes/OQ-17/ and measure determinism and speed on a synthetic monorepo history.
2. Write docs/spikes/oq-17-split-tool.md, update OQ-17 and the roadmap.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

- **Denied command** (auto mode classifier, no reason given): `cmake --build spikes/OQ-17/libgit2-build -j8 && cmake --install spikes/OQ-17/libgit2-build` (install prefix `spikes/OQ-17/prefix`). Not retried. Next run: allow it, or build in another way, then `go build` splitsh-lite with `PKG_CONFIG_PATH=spikes/OQ-17/prefix/lib/pkgconfig`.

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
