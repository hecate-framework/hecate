<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: **First item of Phase 3 (owner decision of 2026-11-13): a readable writing style.** Write a "Writing style" section in `docs/architecture/documentation.md`, after the manner of *Programming in Lua* (Ierusalimschy) [...] Pilot it on the 8 pages written at the Phase 2 gate [...] and submit them to the owner before any other Phase 3 item starts.
- status: waiting-owner
- lock_until: 2026-11-14T00:30:00Z
- last_update: 2026-11-13T23:05:00Z

## Done

1. Claimed the item (this note, draft pull request #195).
2. "Writing style" section in `docs/architecture/documentation.md`, pointer in `website/CLAUDE.md` (the
   `docs-writer` agent already reads both files).
3. The four how-tos restyled (ebcd71b), with factual corrections: the 422 of invalid inputs is built by the input
   step, not the guard; deep extension values fail when answered; `auto` logs no fallback warning; `reuseport` is
   Linux only; `on_unobserved_failure` only if given.
4. The schema reference and the three explanations restyled (73fc583); `depth_limit` follows
   `json.DEFAULT_MAX_DEPTH`.
   Reverted at the owner's request (2026-11-13): the eight pages written at the Phase 2 gate were overwritten,
   which was not the goal of this run. They are back to their `main` versions; the rewrites stay in the history
   (ebcd71b, 73fc583) for reference only.
5. Every new inline snippet run against `packages/*/src` (luv installed with `luarocks install luv`): outputs match.
   Gates: typecheck, lint, check-links, check-glossary, check-docs-examples, check-examples, check-changelog ok.

## Next steps

1. Wait for the owner's answer on how to present the pilot, and their review of the writing style (#195). Apply the owner's
   remarks; once approved, delete this note, tick the roadmap item and keep the pull request ready for review. No
   other Phase 3 item may start before that approval (roadmap).

## Decisions taken (and where they are recorded)

- Work happens on the session branch `claude/sweet-feynman-6v4js8` (the session forbids pushing to another branch),
  not on `claude/relay-writing-style`.

## Doubts and questions for the owner

- How the pilot should be presented, now that the Phase 2 gate pages are kept as they are (asked on #195).
- Statements of the Phase 2 gate pages found not to match the code while rewriting them (not applied, pages
  restored; the 422 logging gap is now a Phase 3 roadmap item): the input step, not the guard, builds the 422 of invalid inputs; extension values deeper than the first
  level fail when the problem is answered (generic 500); `auto` logs no fallback warning and `reuseport` is Linux only
  (OQ-43); a refused or failed `app:reload` raises `SupervisorError`, a `SIGHUP` reload never raises;
  `on_unobserved_failure` only if given; `depth_limit` follows `json.DEFAULT_MAX_DEPTH` (lowered by
  `limits.max_depth`).

## Environment notes

- The cloud setup script had not run: Lua 5.5 was installed with
  `bash tools/bootstrap/bootstrap.sh --prefix /opt/lua-5.5 --link /usr/local/bin` (a first attempt hit a transient
  reset from `www.lua.org`).

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
lua tools/run.lua check-docs-examples
lua tools/run.lua check-links
lua tools/run.lua check-glossary
```
