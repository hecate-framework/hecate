# `hecate-doc`

> Documentation generator and static site builder with an MDN-like theme: guides in Markdown, code reference from LuaLS annotations, API reference from OpenAPI, configuration and error-code references, locales, search.

| | |
|---|---|
| Module | `hecate.doc` |
| Rock | `hecate-doc` |
| Layer | Tooling |
| Roadmap phase | 3 |
| Status | in progress — Markdown renderer, site model (locales with fallback, sidebar, previous/next), original theme on the brand kit, search index, `build` and the LuaLS code reference (reference generator, `gen-reference`) implemented; OpenAPI reference, versioned documentation, development server and runnable examples pending |
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
VitePress-like presentation and the Hecate brand kit. Same day, the owner asked for
third-party dependencies wherever they save time (complete GFM, highlighting for many
languages, no new JavaScript development tool); the first slice below has none, and the
candidates are measured in [spike OQ-39](../../docs/spikes/OQ-39-doc-dependencies.md) and
proposed in [ADR 0022](../../docs/adr/0022-doc-dependencies.md).

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
| `reference` (`hecate.doc.reference`) | `generate(inputs, options)`: pages of the code reference from LuaLS exports (pure); `is_generated(text)`; `GENERATED` (the marker). |
| `reference_site` (`hecate.doc.reference_site`) | `run(options)`: runs LuaLS on the packages, generates and writes the pages (skips with `report.skipped` without LuaLS); `write(fs, out, result, packages)`; `DEFAULT_PACKAGES`. |
| `luals` (`hecate.doc.luals`) | `locate()`, `version(executable)`, `export(executable, source, options)` (the `--doc` JSON export), `PINNED`. |

### Building a site

```sh
lua packages/doc/bin/build.lua website --strict          # writes website/dist (git-ignored)
lua packages/doc/bin/build.lua website --out /tmp/site --base /hecate/ --clean
```

The runner is the bootstrap entry point until `hecate doc build` exists
([automation.md](../../docs/architecture/automation.md)). Options: `--config` (default
`<source>/site.lua`), `--out` (default `<source>/dist`), `--base` (URL path, for GitHub Pages
project sites), `--url` (the origin, for canonical links and the sitemap, overriding the
configuration), `--clean` (empties the output directory, only if a previous build wrote it),
`--strict` (broken links and similar problems fail the build), `--no-git-dates`. Exit codes:
0 built, 1 failed, 2 usage error. Serve the output with any static server.

### Code reference

The reference pages are generated from the JSON export of `lua-language-server --doc` (LuaLS
3.19.1, pinned; owner decision of 2026-10-13: annotate every module table as a `---@class`,
no annotation parser of our own; conventions in
[coding-standards.md](../../docs/architecture/coding-standards.md), "Annotations for the
reference"; choices in OQ-40).

```sh
lua tools/run.lua gen-reference            # writes website/en/reference/<package>/, needs lua-language-server
lua tools/run.lua gen-reference --require  # CI: fail instead of skipping when LuaLS is missing
lua packages/doc/bin/build.lua website --strict --reference   # generate, then build the site
```

One page per package (`index.md`, the module), per class or type (`<Class>.md`) and per function
of the module (`functions/<name>.md`). Every page has the nine sections of the template of
[documentation.md](../../docs/architecture/documentation.md) in order (summary, syntax, parameters
and return values, errors raised, whether it may suspend (`---@async`), examples, specifications,
compatibility, see also), a `generated: true` front matter key and a header comment saying not to
edit it. A class page lists its fields and methods with a stable anchor each (`#name`). Examples
are the tested files `packages/<package>/examples/<symbol>.lua`. The pages are not committed
(git-ignored); the output is deterministic. Documented packages: `core`, `reactor`, `net`.

### Content

`<source>/<locale>/` holds Markdown pages with front matter; `<source>/public/` is copied to
the site root. `en` is the default locale; a page missing in another locale is built from the
default locale with a visible notice. The page title is the single `#` heading of the body; front matter `title` is an optional
override of the label used in navigation, search and `<title>` (OQ-35). Front matter keys: `title`, `description`, `order`
(sidebar order), `hecate` and `lua` (the "written for" line), `layout: home` with
`actions: ["Text | page or URL | primary"]`, `outline: false`, `sidebar: false`,
`last_updated`, `source_revision`, `source` (generated pages: repository path of the Lua file). Callouts: `::: note|tip|warning|danger [title]`. Raw HTML
is not supported (shown as text). Conventions: OQ-35. Site configuration (`site.lua`):
`title`, `description`, `base`, `url`, `default_locale`, `locales`, `nav`, `sidebar`,
`repository`, `edit_link`, `source_edit_link` (edit link of generated pages, from their `source`),
`footer`, `outline`, `strings`, `exclude`; see
`hecate.doc.SiteConfig` and [website/site.lua](../../website/site.lua).

### Theme

One stylesheet built on the brand-kit tokens (light and dark, system preference plus a
toggle), small vanilla JavaScript (theme toggle, menus, copy buttons, outline highlighting,
search dialog), STIX Two Text / Fira Sans / Fira Code, header with logo, section links,
search, locale switch, theme toggle and repository link, sidebar, "On this page" outline,
previous/next cards, edit link, last updated, callouts, responsive down to 390 px. Pages are
readable without JavaScript. Vendored material: [THIRD_PARTY_NOTICES](../../THIRD_PARTY_NOTICES).

### Limits of this first slice

Not implemented: OpenAPI reference, error-code and configuration references, translations of generated pages keyed by symbol, `llms.txt`,
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
src/hecate/doc/reference.lua   code reference pages from the LuaLS export; reference_site.lua, luals.lua
src/hecate/doc/theme/          templates (layout.lua), strings, assets/ (css, js, fonts, brand)
bin/build.lua                  build runner (`--reference` generates the code reference first)
bin/reference.lua              code reference runner (used by `tools/run.lua gen-reference`)
tests/unit/  tests/integration/  tests/fixtures/ (fixture site, golden Markdown, brand tokens, fixture package, its LuaLS export and golden reference pages)
```
