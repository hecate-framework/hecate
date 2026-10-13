# `hecate-doc`

> Documentation generator and static site builder with an MDN-like theme: guides in Markdown, code reference from LuaLS annotations, API reference from OpenAPI, configuration and error-code references, locales, search.

| | |
|---|---|
| Module | `hecate.doc` |
| Rock | `hecate-doc` |
| Layer | Tooling |
| Roadmap phase | 3 |
| Status | in progress — Markdown renderer, site model (locales with fallback, sidebar, previous/next), original theme on the brand kit, search index and `build` implemented; LuaLS code reference, OpenAPI reference, versioned documentation, development server and runnable examples pending |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`openapi`](../openapi), [`schema`](../schema), [`json`](../json) |
| Used by | `cli` |
| Native code | none |
| Specification | [documentation.md](../../docs/architecture/documentation.md) |
| Decisions | [ADR 0012](../../docs/adr/0012-website-generator.md), [ADR 0013](../../docs/adr/0013-english-code-multilingual-documentation.md) |
| Agent | [`pkg-doc`](../../.claude/agents/pkg-doc.md) |
| Repository | read-only mirror `hecate-framework/hecate-doc`, generated from this directory (ADR 0017) |

## Responsibilities

- consume `lua-language-server --doc` JSON export and the route/schema metadata
- render Markdown guides (CommonMark + front matter) and generated reference pages with one MDN-like theme (page template in documentation.md)
- locales with fallback and translation status (`source_revision`)
- static search index
- versioned documentation per minor release
- runnable examples for pure-Lua packages if Lua 5.5 builds to WebAssembly (OQ-11)
- `hecate doc build|serve` for user projects with the same theme, with a base URL option for GitHub Pages project sites
- `llms.txt` and `llms-full.txt` generation
- stable anchors per symbol

## Non-goals

- a general-purpose CMS

## Standards and references

- Diátaxis
- OpenAPI 3.1
- CommonMark

## Public API

All names are fields of `require "hecate.doc"`. Direction recorded by the owner on 2026-10-13
(ADR 0012, still Proposed): `hecate.doc` is our own static site generator with a
VitePress-like presentation and the Hecate brand kit; no third-party dependency.

| Name | Description |
|---|---|
| `build(options)` | Reads `<source>/<locale>/**/*.md`, renders every page of every locale, writes pages, search indexes, theme files and static files to `options.out`, returns a `BuildReport` (`files`, `bytes`, `locales`, `problems`). Options: `config`, `source`, `out`, `fs`, `clean`, `strict`, `last_updated`. Output is deterministic. |
| `load_config(path, fs)` | Loads a `site.lua` (data only: it runs with an empty environment). |
| `normalise_config(raw)` | Validates a site configuration and fills the defaults; raises `core.ConfigurationError` with `context.field`. |
| `Site(options)` | The site model: `load()`, `pages(locale)`, `page(locale, id)`, `emit(write)`, `problems`. |
| `Page` | One page in one locale: `id`, `url`, `title`, `html`, `headings`, `sections`, `fallback`, `meta`. |
| `FileSystem` | Interface (`read`, `write`, `list`, `exists`, `remove_tree`) the builder reads and writes through. |
| `MemoryFileSystem(files?)` | In-memory implementation (tests, embedders). |
| `SystemFileSystem()` | Real file system: `io` for files, the platform shell for directories (OQ-33). |
| `BuildError` | `hecate.doc.BuildError` (a `core.Error`): malformed front matter, unreadable source, clashing URLs, `strict` problems. |
| `markdown.render(source, options?)` | Markdown to HTML (`html`, `title`, `headings`, `sections`, `links`); escaping is the default. |
| `front_matter.parse(source, path?)` | Splits front matter (flat YAML subset) from the body. |
| `highlight.render(language, code)` | Syntax highlighting for Lua, JSON, shell, HTTP and diff. |
| `navigation` | `sidebar`, `reading_order`, `neighbours`, `top_links`, `section_of` (pure functions). |
| `search.build(locale, pages)`, `search.encode(index)` | The client-side search index. |
| `theme` | `page(context)`, `not_found(context)`, `strings`, `asset_files`, `assets_directory()`. |

### Building a site

```sh
lua packages/doc/bin/build.lua website --strict          # writes website/dist (git-ignored)
lua packages/doc/bin/build.lua website --out /tmp/site --base /hecate/ --clean
```

The runner is the bootstrap entry point until `hecate doc build` exists
([automation.md](../../docs/architecture/automation.md)). Options: `--config` (default
`<source>/site.lua`), `--out` (default `<source>/dist`), `--base` (URL path, for GitHub Pages
project sites), `--clean` (empties the output directory, only if a previous build wrote it),
`--strict` (broken links and similar problems fail the build), `--no-git-dates`. Exit codes:
0 built, 1 failed, 2 usage error. Serve the output with any static server.

### Content

`<source>/<locale>/` holds Markdown pages with front matter; `<source>/public/` is copied to
the site root. `en` is the default locale; a page missing in another locale is built from the
default locale with a visible notice. Front matter keys: `title`, `description`, `order`
(sidebar order), `hecate` and `lua` (the "written for" line), `layout: home` with
`actions: ["Text | page or URL | primary"]`, `outline: false`, `sidebar: false`,
`last_updated`, `source_revision`. Callouts: `::: note|tip|warning|danger [title]`. Raw HTML
is not supported (shown as text). Conventions: OQ-35. Site configuration (`site.lua`):
`title`, `description`, `base`, `url`, `default_locale`, `locales`, `nav`, `sidebar`,
`repository`, `edit_link`, `footer`, `outline`, `strings`, `exclude`; see
`hecate.doc.SiteConfig` and [website/site.lua](../../website/site.lua).

### Theme

One stylesheet built on the brand-kit tokens (light and dark, system preference plus a
toggle), small vanilla JavaScript (theme toggle, menus, copy buttons, outline highlighting,
search dialog), STIX Two Text / Fira Sans / Fira Code, header with logo, section links,
search, locale switch, theme toggle and repository link, sidebar, "On this page" outline,
previous/next cards, edit link, last updated, callouts, responsive down to 390 px. Pages are
readable without JavaScript. Vendored material: [THIRD_PARTY_NOTICES](../../THIRD_PARTY_NOTICES).

### Limits of this first slice

Not implemented: LuaLS code reference and OpenAPI reference generation, `llms.txt`,
versioned documentation, development server, runnable examples, translation status report,
extension points of the theme for user projects (OQ-38). Markdown is a CommonMark subset
(OQ-37). The search ranking is client-side JavaScript without an automated test (OQ-36).
Verified on Linux; macOS and Windows are verified by CI only (the shell calls of
`SystemFileSystem` are the platform-specific part, OQ-33).

## Layout

```text
src/hecate/doc/init.lua        public entry point
src/hecate/doc/markdown.lua    block renderer; internal/inline.lua inline renderer
src/hecate/doc/site.lua        content tree, locales, links, navigation, output
src/hecate/doc/theme/          templates (layout.lua), strings, assets/ (css, js, fonts, brand)
bin/build.lua                  build runner
tests/unit/  tests/integration/  tests/fixtures/ (fixture site, golden Markdown, brand tokens)
```
