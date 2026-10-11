# Website

Public documentation of Hecate. Generator: `hecate.doc` with an MDN-like theme (ADR 0012,
Proposed, owner preference; spike OQ-11 confirms). Pages are plain Markdown with front
matter, independent of the generator. English is
the source (`en/`); translations mirror it (`fr/` first). Specification:
[docs/architecture/documentation.md](../docs/architecture/documentation.md).
Site map: [OUTLINE.md](OUTLINE.md).

Nothing is built yet: the skeleton is a Phase 3 roadmap item (pages can be drafted
earlier as Markdown).

## Planned layout

```text
website/
  site.lua                  site configuration for hecate.doc: locales, navigation, search
  public/llms.txt           generated
  en/                       English source
    tutorials/ how-to/ reference/ explanation/ community/
    reference/              generated (never edited by hand)
  fr/                       French translation, same tree
```
