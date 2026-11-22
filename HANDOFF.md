<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `website`: move the Hecate website into `website/user/` and `website/maintainer/` (OQ-144, owner decisions of 2026-11-21), before `0.1.0`
- status: in-progress
- lock_until: 2026-11-22T14:11:46Z
- last_update: 2026-11-22T12:41:46Z

## Done

- Claimed the item (branch, handoff, draft pull request). No content moved yet.
- Merged `main` (899c5d4); CI green on the three platforms for #229.
- Read the classification and the link checker. Findings: `tools/lib/links.lua` (`is_ungenerated_reference`, patterns `^website/[^/]+/reference/...`) and `tools/tests/links_test.lua` hard-code `website/<locale>/`; they must become `website/<tree>/<locale>/`. Same for `tools/tasks/{gen_reference,gen_error_codes,gen_config_reference,check_docs_examples}.lua`, `tools/lib/generated_page.lua`, `.gitignore`, `.github/labeler.yml`, `tools/tests/{changes,examples}_test.lua`.
- Moved the pages: `website/en|fr` -> `website/user/en|fr`; `architecture-and-layers` and `measure-performance` (en, fr) -> `website/maintainer/`. Path references updated in tools, `.gitignore`, labeler, package tests and READMEs, architecture docs, roadmap, OUTLINE. Baseline failures unchanged (native modules not built here; 4 benchmark port tests).

## Next steps

0. **Broken links left (`lua tools/run.lua check-links`, 21):** maintainer pages -> user pages (glossary, filters, object-model...) and user index pages -> the two maintainer pages. Decide the cross-tree link form (absolute URL, `site_origin`-based) and teach `check-links` to resolve it across trees; `fr` links to `measure-performance` too. Also create `maintainer/en/index.md`, `website/user/en/explanation/life-of-a-request.md`, `site.lua` (one for both; the builder takes one tree per site), the `build` and CI website workflow paths, `website/README.md`, `CLAUDE.md`, `.claude/agents/docs-writer.md`.

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
