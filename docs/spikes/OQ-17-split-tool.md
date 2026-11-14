# OQ-17: split tool for the read-only mirrors

Question: which tool splits `packages/<name>` of the monorepo into the history of
`hecate-framework/hecate-<name>` (ADR 0017, `split.yml`): `splitsh-lite`, `git subtree split` or
`git filter-repo`? Criteria: determinism, speed, maintenance. Windows is irrelevant (the split runs in CI on Linux).

## Method

Date 2026-11-14, Linux x86_64, git 2.43.0, Go from the image. The history is the repository itself, fully
fetched: 1026 commits, 30 packages. For `packages/core`, `packages/http` and `packages/json`, each tool ran on two
independent fresh clones (`git clone --no-local`), cold (no cache). Third-party code was built under `spikes/OQ-17/`
(git-ignored): `splitsh-lite` at `36e0e74` (2025-11-30), `git-filter-repo` at `d7b75ac` (2026-07-09), libgit2 v1.5.0.

## Findings

| | `splitsh-lite` | `git subtree split` | `git filter-repo --subdirectory-filter` |
|---|---|---|---|
| Time, cold, 1026 commits (core / http / json) | 0.11 / 0.12 to 0.17 / 0.13 to 0.16 s | 8.7 to 9.1 / 9.4 to 9.9 / 8.7 to 9.0 s | 0.34 / 0.43 / not run s |
| Time, nothing new | 0.04 s (cache `.git/splitsh.db`) | same as cold | same as cold |
| Same result on two clones | yes | yes | yes |
| Commits of `core` / `http` | 24 / 57 | 24 / 57 | 31 / 64 |
| Commit SHAs equal to `splitsh-lite` | (reference) | **yes, all three packages** | no (different commit set), trees equal |
| Incremental: two new commits | 1 commit created, parent is the previous tip | whole history walked again, same result | not incremental: needs a fresh clone each time |
| Writes in the repository | cache file only | creates a branch | **rewrites the clone** (needs `--force` or a throwaway clone) |
| Build | cgo, **libgit2 exactly 1.5.0** (git2go v34 refuses 1.7); built from source here | none, ships with git | Python 3 script, no build |
| Maintenance | last commit 2025-11-30, one-year gap | git itself | active (2026-07) |

`splitsh-lite` and `git subtree split` produce byte-identical histories (same SHAs), so switching later from one to the
other does not rewrite a mirror. `filter-repo` produces the same final trees but a different commit graph (it keeps
7 and 7 more commits on these packages), so changing to or from it would rewrite the history of every mirror.

Cost extrapolation: `git subtree split` costs about 9 ms per commit per package; at 20 000 commits and 30 packages
that is about 3 minutes per package, 90 minutes per run. `splitsh-lite` costs about 0.1 ms per commit cold and is
incremental.

## Recommendation (for the owner)

`splitsh-lite`, pinned (commit sha and libgit2 1.5.0 built in the workflow, cached), with `git subtree split` as the
documented fallback: the two give the same SHAs, so the fallback is a zero-impact change if `splitsh-lite` is abandoned.
Not `filter-repo`: it rewrites its input, is not incremental, and yields a different history.

## Remaining risks

- `splitsh-lite` pins an old libgit2 and has a slow maintenance pace; building it is the only non-trivial CI step.
  A new tool needs an ADR (CLAUDE.md); a CI-only build tool probably counts as one (owner to say).
- Measured on 1026 commits with no merges from forks; re-measure when the history is ten times larger.
- Tags and the injection of `.github/mirror-template/` were not measured (the second is done after the split).
