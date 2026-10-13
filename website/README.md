# Website

Public documentation of Hecate. Generator: `hecate.doc` with an MDN-like theme (ADR 0012,
Proposed, owner preference; spike OQ-11 confirms). Pages are plain Markdown with front
matter, independent of the generator. English is
the source (`en/`); translations mirror it (`fr/` first). Specification:
[docs/architecture/documentation.md](../docs/architecture/documentation.md).
Site map: [OUTLINE.md](OUTLINE.md).

The site is built by `hecate.doc` (first slice implemented; see
[packages/doc/README.md](../packages/doc/README.md)):

```sh
lua packages/doc/bin/build.lua website --strict    # output: website/dist (git-ignored)
```

Conventions of the pages (front matter, callouts, links between pages as `.md` files,
`README.md` files are not published): [packages/doc/README.md](../packages/doc/README.md).
The glossary page is a hand-adapted public copy of `docs/glossary.md`: keep it in step.

## Planned layout

```text
website/
  site.lua                  site configuration for hecate.doc: locales, navigation, edit link
  public/llms.txt           generated (not yet)
  en/                       English source
    tutorials/ how-to/ reference/ explanation/ community/
    reference/              generated (never edited by hand)
  fr/                       French translation, same tree
```
