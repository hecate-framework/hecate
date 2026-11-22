<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `website`: move the Hecate website into `website/user/` and `website/maintainer/` (OQ-144, owner decisions of 2026-11-21), before `0.1.0`
- status: in-progress
- lock_until: 2026-11-22T09:40:30Z
- last_update: 2026-11-22T08:10:30Z

## Done

- Claimed the item (branch, handoff, draft pull request). No content moved yet.

## Next steps

1. Read `docs/reviews/website-audience-classification.md` in full, `website/site.lua`, and the tools that read `website/en` and `website/fr` (`gen-reference`, `gen-error-codes`, `gen-config-reference`, `check-links`, `check-docs-examples`, `check-examples`, `.gitignore`).
2. Tests first: a `check-links` test for links between the two trees.
3. `git mv` the pages (English and French together) into `website/user/<locale>/` and `website/maintainer/<locale>/` per the classification.
4. Split "The life of a request" into `explanation/life-of-a-request.md` (user, with the French page).
5. One `site.lua`, edit-link template naming the tree directory, `top_links` to the other site, `/` redirecting to the user site.
6. Split the code reference with `reference_site.run` and `audience_locale_dirs`.
7. Task that writes `docs/architecture/` and the ADRs into the maintainer tree (settle the mechanism, record it).
8. Update generators, `.gitignore`, `website/CLAUDE.md`, `OUTLINE.md`, CHANGELOG, roadmap; run `/review-package doc`; CI on three platforms.

## Decisions taken (and where they are recorded)

none yet

## Doubts and questions for the owner

none yet

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
