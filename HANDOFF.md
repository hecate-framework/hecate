<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `website`: move the Hecate website into `website/user/` and `website/maintainer/` (OQ-144, owner decisions of 2026-11-21), before `0.1.0`
- status: in-progress
- lock_until: 2026-11-22T15:56:40Z
- last_update: 2026-11-22T14:26:40Z

## Done

- Claimed the item (branch, handoff, draft pull request). No content moved yet.
- Merged `main` (899c5d4); CI green on the three platforms for #229.
- Read the classification and the link checker. Findings: `tools/lib/links.lua` (`is_ungenerated_reference`, patterns `^website/[^/]+/reference/...`) and `tools/tests/links_test.lua` hard-code `website/<locale>/`; they must become `website/<tree>/<locale>/`. Same for `tools/tasks/{gen_reference,gen_error_codes,gen_config_reference,check_docs_examples}.lua`, `tools/lib/generated_page.lua`, `.gitignore`, `.github/labeler.yml`, `tools/tests/{changes,examples}_test.lua`.
- Moved the pages: `website/en|fr` -> `website/user/en|fr`; `architecture-and-layers` and `measure-performance` (en, fr) -> `website/maintainer/`. Path references updated in tools, `.gitignore`, labeler, package tests and READMEs, architecture docs, roadmap, OUTLINE. Baseline failures unchanged (native modules not built here; 4 benchmark port tests).

- Step 2: links between the two sites are browser-relative URLs (`../../../../maintainer/en/explanation/x/`, the form of documentation.md); `check-links` resolves them across trees (`links.cross_tree_target`, test first); the 21 broken links rewritten. `check-links`, typecheck, lint green.
- Step 3: one build per tree. `maintainer/en/index.md`; `site.lua` edit link template `website/{tree}/{path}` (`{tree}` filled by `bin/build.lua`, and by the repository-website test); the `doc` integration test builds both trees (all `doc` tests green locally after `build-native json doc` and `luarocks --tree .hecate/rocks install luv`); `website.yml` builds `dist/user` (with `--reference`) and `dist/maintainer`, bases `<base>/user/` and `<base>/maintainer/`, `dist/index.html` redirects to the user site; reference checks use `dist/user`.
- CI fixes after 2ed33fe (resumed 14:14 UTC): `lychee.toml` excludes updated to the tree layout and the cross-site URLs; `website.yml` passes `--root .` to the user build (default root was `website/`); build commands in READMEs updated. Lychee reproduced locally: 0 errors.
- `life-of-a-request` user page (en only; no fr source). Code reference split: `bin/build.lua --internals-into`, workflow and .gitignore updated; both sites built locally in `--strict` (user 473 pages, maintainer 25) after `build-native json doc`, `luarocks --tree .hecate/rocks install luv`, `setup-luals`, `LUA_CPATH=.hecate/rocks/lib/lua/5.5/?.so`, luals on PATH.

## Next steps

00. Left: generated architecture and ADR pages in the maintainer tree (task, links rewritten, git-ignored), fr `life-of-a-request` (translator-fr), `CLAUDE.md` and `docs-writer` notes, OQ entry (+ issue) for the `{tree}` placeholder, `/review-package doc`, roadmap tick, `typecheck`.

0. Still to do: `website/user/en/explanation/life-of-a-request.md` (split, with fr), `website/README.md`, `website/CLAUDE.md`, `CLAUDE.md`, `.claude/agents/docs-writer.md`, CHANGELOG, roadmap, `/review-package doc`, CI on three platforms (the website workflow runs on this PR: check it).

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

- OQ-144 says the edit-link template "already names the tree directory", but the template is one for both sites while `{path}` is relative to the content root of a tree. Conservative choice taken: a `{tree}` placeholder in the template filled by the bootstrap builder (`bin/build.lua`); to record as an open-question entry (and issue) at the finish step if it stays.

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
