<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: **First item of Phase 3 (owner decision of 2026-11-13): a readable writing style.** Write a "Writing style" section in `docs/architecture/documentation.md`, after the manner of *Programming in Lua* (Ierusalimschy) [...] Pilot it on the 8 pages written at the Phase 2 gate [...] and submit them to the owner before any other Phase 3 item starts.
- status: in-progress
- lock_until: 2026-11-14T08:19:33Z
- last_update: 2026-11-14T06:49:33Z

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
6. Step 1 of the owner instruction done: the pilot pages were checked against the code for every candidate statement;
   only `multi-process-deployment.md` was wrong (an `auto` fallback logs no warning, only an explicit `reuseport` does,
   `listening.select`). The others match: `SupervisorError` `crash_loop`/`reload_failed`, `on_unobserved_failure`,
   the 422 of the inputs.

7. Restyle group 1 (7 how-tos) done with the docs-writer agent, claims checked against the code (json depth/size
   limits, benchmark rounds and pinning, config secrets, sink defaults, container override, `auto` strategy, offload
   limits); gates typecheck, check-docs-examples, check-links, check-glossary ok.

## Next steps

(Group 1 done, see Done 7.)

Owner instruction (2026-11-13, on #195): the eight Phase 2 gate pages are the approved pilot and stay as they are,
except the statements that do not fit the code exactly (verify thoroughly before asserting). This run's goal is to
bring every other English page to the same standard and style (the "apply the writing style to every page" part of
the Website item).

3. Restyle group 2: how-to `deadlines-and-cancellation`, `udp-pipes-and-dns`, `connect-and-serve-over-tcp`,
   `run-processes-and-pass-connections`, `tls-client-and-server`.
4. Restyle group 3: how-to `serve-http`, `stream-http-content`, `use-the-http-client`, `http-limits-timeouts-and-tls`,
   `handle-forms-and-multipart`, `route-requests`.
5. Restyle group 4: how-to `validate-with-schemas`, explanation `schemas-and-contracts`.
6. Restyle group 5: explanations `tls-trust-and-security`, `transport-model`, `http-model`, `multi-process-serving`,
   and the index pages (`index.md`, `how-to/index.md`, `explanation/index.md`, `reference/index.md`).
7. Tick the first Phase 3 item, record the style part of the Website item as done, CHANGELOG, gates, ready for
   review.

## Decisions taken (and where they are recorded)

- Work happens on the session branch `claude/sweet-feynman-6v4js8` (the session forbids pushing to another branch),
  not on `claude/relay-writing-style`.

## Doubts and questions for the owner

- Candidate statements of the Phase 2 gate pages that may not match the code while rewriting them (not applied, pages
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
