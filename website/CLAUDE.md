# Agent context — `website/`

Agents: `docs-writer` (English source), `translator-fr` (French).

- Structure: Diátaxis (tutorials, how-to, reference, explanation). See `OUTLINE.md`.
- `en/` is the source. `fr/` mirrors its tree; each translated page has front matter
  `source_revision: <commit>` of the English page it translates.
- `*/reference/<package>/**` and the pages `reference/error-codes.md` and `reference/configuration-keys.md` are generated
  (`gen-reference`, `gen-error-codes`, `gen-config-reference`, `hecate doc`) and git-ignored: never edit them by hand.
  The other pages of `reference/` (`index.md`, `glossary.md`, `schema-keywords-and-formats.md`) are hand-written.
- Code samples are included from tested files (`packages/<name>/examples/`,
  `examples/`), never written inline when they exceed a few lines.
- Code examples follow the two rules of `docs/architecture/documentation.md`, "Code examples": no line holding a
  comment is longer than 80 characters (`check-examples`), and what a line prints is written in a `-- Prints:` block
  directly under that line, never gathered at the end.
- Each page front matter: `description`, `hecate: "0.x"`, `lua: "5.5"`; `title` only to override the navigation label (the page title is the `#` heading).
- Use glossary vocabulary; link the first occurrence of a term to the glossary page.
- After adding a page: update `OUTLINE.md` and regenerate `llms.txt`.
