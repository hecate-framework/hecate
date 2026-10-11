---
description: Translate or refresh a website page
---

Translate: $ARGUMENTS (format: `<page path under website/en> <locale>`)

Use the `translator-<locale>` agent if it exists, otherwise follow
`website/CLAUDE.md`. Preserve structure, anchors, code and front matter; set
`source_revision` to the current commit of the English source.
