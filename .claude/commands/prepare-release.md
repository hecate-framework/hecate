---
description: Prepare a release (no publishing)
---

Prepare release: $ARGUMENTS

With the `release-manager` agent: run `release prepare` and `release verify` when they
exist (otherwise follow versioning-and-distribution.md by hand), produce release notes
starting with `Hecate X.Y.Z — Lua 5.5`, list breaking changes with migration notes, and
stop before tagging. The owner tags and publishes.
