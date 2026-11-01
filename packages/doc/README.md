# `hecate-doc`

> Documentation generator and static site builder with an MDN-like theme: guides in Markdown, code reference from LuaLS annotations, API reference from OpenAPI, configuration and error-code references, locales, search.

| | |
|---|---|
| Module | `hecate.doc` |
| Rock | `hecate-doc` |
| Layer | Tooling |
| Roadmap phase | 3 |
| Status | alpha — minimal slice done (Phase 1 roadmap item); the roadmap phase stays 3 because the package is still in progress for it: Markdown rendering and highlighting by the native module (comrak, syntect), site model (locales with fallback, sidebar, previous/next), original theme on the brand kit, search index, `build` and the LuaLS code reference (reference generator, `gen-reference`) implemented; OpenAPI reference, versioned documentation, development server, runnable examples, `hecate doc build` for user projects and the prebuilt binary rocks of the native module pending (Phase 3) |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`reactor`](../reactor), [`openapi`](../openapi), [`schema`](../schema), [`json`](../json) |
| Used by | `cli` |
| Native code | Rust (`native/`): comrak (Markdown) and syntect with two-face (highlighting), through `mlua` (ADR 0022) |
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
(ADR 0012, Accepted): `hecate.doc` is our own static site generator with a
VitePress-like presentation and the Hecate brand kit. Same day, the owner asked for
third-party dependencies wherever they save time (complete GFM, highlighting for many
languages, no new JavaScript development tool); ADR 0022 (Accepted) lists them; the
measurements are in [spike OQ-39](../../docs/spikes/OQ-39-doc-dependencies.md) and
decided in [ADR 0022](../../docs/adr/0022-doc-dependencies.md).

| Name | Description |
|---|---|
| `build(options)` | Reads `<source>/<locale>/**/*.md`, renders every page of every locale, writes pages, search indexes, theme files and static files to `options.out`, returns a `BuildReport` (`files`, `bytes`, `locales`, `problems`). Options: `config`, `source`, `out`, `fs`, `clean`, `strict`, `last_updated`. Output is deterministic. |
| `load_config(path, fs)` | Loads a `site.lua` (data only: it runs with an empty environment). |
| `normalise_config(raw)` | Validates every key of a site configuration (type and shape; `base` must be an absolute path and not protocol-relative, `url` an http(s) origin) and fills the defaults; raises `core.ConfigurationError` with `context.field` naming the offending key. |
| `Site(options)` | The site model: `load()`, `pages(locale)`, `page(locale, id)`, `emit(write)`, `problems`. |
| `Page` | One page in one locale: `id`, `url`, `title`, `html`, `headings`, `sections`, `fallback`, `meta`. |
| `FileSystem` | Interface (`read`, `write`, `list`, `exists`, `remove_tree`; optional `is_link`) the builder reads and writes through. `remove_tree` unlinks a symbolic link at its path, never its target; `build` with `clean` refuses an output directory that is a symbolic link. |
| `MemoryFileSystem(files?)` | In-memory implementation (tests, embedders). |
| `SystemFileSystem()` | Real file system over `hecate.reactor.fs`; every method suspends, so call it inside `reactor.run` (OQ-33). |
| `BuildError` | `hecate.doc.BuildError` (a `core.Error`): malformed front matter, unreadable source, clashing URLs, `strict` problems, a file system failure (`SystemFileSystem`), a failed LuaLS export, a page that is not valid UTF-8, a file of `public/` that collides with a generated file, two output files whose paths differ only by case (one file on macOS and Windows). |
| `markdown.render(source, options?)` | Markdown to HTML (`html`, `title`, `headings`, `sections`, `links`); safe mode only (raw HTML is not passed through); a source that is not valid UTF-8 raises `core.ArgumentError`. |
| `front_matter.parse(source, path?)` | Splits front matter (flat YAML subset) from the body; double-quoted scalars accept only the escapes `\\`, `\"`, `\n`, `\t` (any other backslash sequence is a `BuildError`). |
| `luals` (`hecate.doc.luals`) | `locate()`, `version(executable)`, `export(executable, source, options)` (output in a private directory removed afterwards: `mktemp -d` on POSIX; on Windows a new directory below `TEMP`/`TMP` with an unpredictable name, never reused if it exists: `windows_temporary_directory(getenv, parts)`, `claim_directory(fs, path)`), `command_line(...)` and `quote(path, windows?)` (pure; shell quoting for POSIX and `cmd.exe`). |
| `highlight.render(language, code)` | Syntax highlighting by syntect (two-face syntaxes, `hl-` classes); an unknown language is escaped and left plain. |
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
(git-ignored); the output is deterministic. Documented packages: `core`, `reactor`, `net`, `json`, `log` (`reference_site.DEFAULT_PACKAGES`).

### Content

`<source>/<locale>/` holds Markdown pages with front matter; `<source>/public/` is copied to
the site root (hidden files excepted). A file of `public/` that has the path of a generated file (a page, `404.html`, `index.html`, `sitemap.xml`, `assets/...`) is a `BuildError`: generated files are never overwritten, and never overwrite hand-made ones silently. Page paths are percent-encoded in URLs (RFC 3986), files keep their real names on disk. `en` is the default locale; a page missing in another locale is built from the
default locale with a visible notice. The page title is the single `#` heading of the body; front matter `title` is an optional
override of the label used in navigation, search and `<title>` (OQ-35). Front matter keys: `title`, `description`, `order`
(sidebar order), `hecate` and `lua` (the "written for" line), `layout: home` with
`actions: ["Text | page or URL | primary"]`, `outline: false`, `sidebar: false`,
`last_updated`, `source_revision`, `source` (generated pages: repository path of the Lua file). Callouts are GFM alerts: `> [!NOTE|TIP|IMPORTANT|WARNING|CAUTION] [title]`. Raw HTML
is not supported (shown as text, comments are dropped). Conventions: OQ-35. Site configuration (`site.lua`):
`title`, `description`, `base`, `url`, `default_locale`, `locales`, `nav`, `sidebar`,
`repository`, `edit_link`, `source_edit_link` (edit link of generated pages, from their `source`),
`footer`, `outline`, `strings`, `exclude`; see
`hecate.doc.SiteConfig` and [website/site.lua](../../website/site.lua).

`bin/build.lua` parses its command line strictly: an unknown option, an option without value, a repeated option or a second source directory is a usage error (exit code 2); `--flag=value` is accepted; `--base` and `--url` are validated like the configuration keys.

### Native module and the specification examples

The shipped native module exports `render` and `highlight` only (safe mode). The unsafe renderer that runs the CommonMark and GFM specification examples (OQ-37) is compiled only with the cargo feature `spec-tests`: `cargo build --release --features spec-tests --target-dir target/spec` in `native/` (or point `HECATE_DOC_SPEC_LIB` at the library); without that build `commonmark_spec_test.lua` skips.

### Theme

One stylesheet built on the brand-kit tokens (light and dark, system preference plus a
toggle), small vanilla JavaScript (theme toggle, menus, copy buttons, outline highlighting,
search dialog), STIX Two Text / Fira Sans / Fira Code, header with logo, section links,
search, locale switch, theme toggle and repository link, sidebar, "On this page" outline,
previous/next cards, edit link, last updated, callouts, responsive down to 390 px. Pages are
readable without JavaScript. Vendored material: [THIRD_PARTY_NOTICES](../../THIRD_PARTY_NOTICES).

### Limits of the current implementation

Not implemented: OpenAPI reference, error-code and configuration references, translations of generated pages keyed by symbol, `llms.txt`,
versioned documentation, development server, runnable examples, translation status report,
extension points of the theme for user projects (OQ-38). Markdown is GFM through comrak; the CommonMark 0.31.2 and GFM extension examples run as a test through the module (OQ-37). The search ranking is client-side JavaScript without an automated test (OQ-36).
Verified on Linux; macOS and Windows are verified by CI only (the shell calls of
`SystemFileSystem` are the platform-specific part, OQ-33).

## Layout

```text
src/hecate/doc/init.lua        public entry point
src/hecate/doc/markdown.lua    Markdown (comrak) and highlight.lua (syntect) over the native module
native/                        the Rust crate (comrak, syntect, two-face; `lua tools/run.lua build-native doc`)
src/hecate/doc/site.lua        content tree, locales, links, navigation, output
src/hecate/doc/reference.lua   code reference pages from the LuaLS export; reference_site.lua, luals.lua
src/hecate/doc/theme/          templates (layout.lua), strings, assets/ (css, js, fonts, brand)
bin/build.lua                  build runner (`--reference` generates the code reference first)
bin/reference.lua              code reference runner (used by `tools/run.lua gen-reference`)
tests/unit/  tests/integration/  tests/fixtures/ (fixture site, golden Markdown, brand tokens, fixture package, its LuaLS export and golden reference pages)
```
