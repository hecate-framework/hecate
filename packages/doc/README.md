# `hecate-doc`

> Documentation generator and static site builder with an MDN-like theme: guides in Markdown, code reference from LuaLS annotations, configuration reference, locales, search.

| | |
|---|---|
| Module | `hecate.doc` |
| Rock | `hecate-doc` |
| Layer | Tooling |
| Roadmap phase | 3 |
| Status | alpha — minimal slice done (Phase 1 roadmap item); the roadmap phase stays 3 because the package is still in progress for it: Markdown rendering and highlighting by the native module (comrak, syntect), site model (locales with fallback, sidebar, previous/next), original theme on the brand kit, search index, `build` and the LuaLS code reference (reference generator, `gen-reference`) implemented; the project documentation (`hecate.doc.project`: configuration reference, LuaLS meta files) and `generate_project_documentation` (the documentation of a project with the defaults of the conventional layout) and the theme extension points (`logo`, `favicon`, `sidebar_marker`, `theme`) and `llms.txt` / `llms-full.txt` (opt-in) implemented; versioned documentation, development server, runnable examples, the `hecate doc build` command and the prebuilt binary rocks of the native module pending (Phase 3) |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`reactor`](../reactor), [`openapi`](../openapi), [`schema`](../schema), [`json`](../json), [`unicode`](../unicode) |
| Used by | `cli` |
| Native code | Rust (`native/`): comrak (Markdown) and syntect with two-face (highlighting), through `mlua` (ADR 0022) |
| Specification | [documentation.md](../../docs/architecture/documentation.md) |
| Decisions | [ADR 0012](../../docs/adr/0012-website-generator.md), [ADR 0013](../../docs/adr/0013-english-code-multilingual-documentation.md) |
| Agent | [`pkg-doc`](../../.claude/agents/pkg-doc.md) |
| Repository | read-only mirror `hecate-framework/hecate-doc`, generated from this directory (ADR 0017) |

## Responsibilities

- consume `lua-language-server --doc` JSON export and the schema metadata
- render Markdown guides (CommonMark + front matter) and generated reference pages with one MDN-like theme (page template in documentation.md)
- locales with fallback and translation status (`source_revision`)
- static search index
- versioned documentation per minor release
- runnable examples for pure-Lua packages if Lua 5.5 builds to WebAssembly (OQ-11)
- `hecate doc build|serve` for user projects with the same theme, with a base URL option for GitHub Pages project sites
- `llms.txt` and `llms-full.txt` generation (site configuration `llms`, off by default)
- stable anchors per symbol

## Non-goals

- a general-purpose CMS
- an API reference: the OpenAPI contract is the external documentation, and any viewer is the user's own wiring (OQ-141)

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
| `build(options)` | Reads `<source>/<locale>/**/*.md`, renders every page of every locale, writes pages, search indexes, theme files and static files to `options.out`, returns a `BuildReport` (`files`, `bytes`, `locales`, `problems`, `sites`: one entry per site written with its `audiences`, `directory`, `files`, `bytes`, `locales` and `problems`). Options: `config`, `source`, `out`, `fs`, `clean`, `strict`, `last_updated`. `BuildReport.locales[code]` has `pages`, `fallbacks` and `unpublished` (pages left out by their audience). Output is deterministic. |
| `generate_project_documentation(options?)` | The documentation of a Hecate project: writes the guides given as text and the generated pages (configuration reference, licences page, code reference) into the guides directory, then builds the site. Every option has a default of the conventional layout (see "Documentation of a project"); returns a `ProjectDocumentationReport` (a `BuildReport`, plus `code`). Unlike `build`, which only turns a content tree into a site. |
| `load_config(path, fs)` | Loads a `site.lua` (data only: it runs with an empty environment). |
| `normalise_config(raw)` | Validates every key of a site configuration (type and shape; `base` must be an absolute path and not protocol-relative, `url` an http(s) origin) and fills the defaults; raises `core.ConfigurationError` with `context.field` naming the offending key. |
| `Site(options)` | The site model: `load()`, `pages(locale)`, `page(locale, id)`, `unpublished(locale)`, `emit(write)`, `problems`. |
| `Page` | One page in one locale: `id`, `url`, `title`, `html`, `headings`, `sections`, `fallback`, `meta`. |
| `FileSystem` | Interface (`read`, `write`, `list`, `exists`, `remove_tree`; optional `is_link`) the builder reads and writes through. `remove_tree` unlinks a symbolic link at its path, never its target; `build` with `clean` refuses an output directory that is a symbolic link. |
| `MemoryFileSystem(files?)` | In-memory implementation (tests, embedders). |
| `SystemFileSystem()` | Real file system over `hecate.reactor.fs`; every method suspends, so call it inside `reactor.run` (OQ-33). |
| `BuildError` | `hecate.doc.BuildError` (a `core.Error`): malformed front matter, unreadable source, clashing URLs, `strict` problems, a file system failure (`SystemFileSystem`), a failed LuaLS export, a page that is not valid UTF-8, a page id that is not a valid file name on Windows (`? : * " < > \| \` and control characters, a trailing dot or space, the device names `CON`, `PRN`, `AUX`, `NUL`, `COM1` to `COM9`, `LPT1` to `LPT9`, `CONIN$`, `CONOUT$`, `CLOCK$` in any case and with an extension; only page ids are checked, not the names of other files of the tree or of `public/`), two pages whose ids differ only by case, two files whose ids differ only in Unicode normalisation (NFC and NFD), a file of `public/` that collides with a generated file, two output files whose paths differ only by case (one file on macOS and Windows). |
| `markdown.render(source, options?)` | Markdown to HTML (`html`, `title`, `headings`, `sections`, `links`); safe mode only (raw HTML is not passed through); a source that is not valid UTF-8, or in which a line opens more than 100 block containers (`>` quotes and list items; the nesting limit), raises `core.ArgumentError`. |
| `front_matter.parse(source, path?)` | Splits front matter (flat YAML subset) from the body; double-quoted scalars accept only the escapes `\\`, `\"`, `\n`, `\t` (any other backslash sequence is a `BuildError`). |
| `luals` (`hecate.doc.luals`) | `locate()`, `version(executable)`, `export(executable, source, options)` (output in a private directory removed afterwards: `mktemp -d` on POSIX; on Windows a new directory below `TEMP`/`TMP` with an unpredictable name, never reused if it exists: `windows_temporary_directory(getenv, parts)`, `claim_directory(fs, path)`), `command_line(...)` and `quote(path, windows?)` (pure; shell quoting for POSIX and `cmd.exe`), `excerpt(output)` (the first lines of a failed run, used in the `BuildError`), `PINNED`. `export` runs the plugin of the `.luarc.json` it is given: document trusted sources only. |
| `highlight.render(language, code)` | Syntax highlighting by syntect (two-face syntaxes, `hl-` classes); an unknown language is escaped and left plain. |
| `navigation` | `sidebar`, `reading_order`, `neighbours`, `top_links`, `section_of` (pure functions). |
| `search.build(locale, pages)`, `search.encode(index)` | The client-side search index. |
| `theme` | `page(context)`, `not_found(context)`, `strings`, `asset_files`, `diagram_files` (written only when a page holds a diagram), `assets_directory()`. |
| `reference` (`hecate.doc.reference`) | `generate(inputs, options)`: pages of the code reference from LuaLS exports (pure; option `internal` adds the `maintainer` pages of `*.internal` modules and of non-public classes, `label_audiences` writes the `audience` key on every page); `is_generated(text)`; `GENERATED` (the marker). |
| `reference_site` (`hecate.doc.reference_site`) | `run(options)`: runs LuaLS on the packages, generates and writes the pages (skips with `report.skipped` without LuaLS); `write(fs, out, result, packages)`; `DEFAULT_PACKAGES`. |
| `project` (`hecate.doc.project`) | `configuration_page(schema, options?)`: the configuration reference from a JSON Schema, a `maintainer` page that prints `[redacted]` for the default of a secret key (`writeOnly`, `format: "password"`, or `options.secrets`); `meta(schemas, namespace)`: a LuaLS `---@meta` declaration file (classes, aliases) from named JSON Schemas (OQ-96); `is_generated(text)`. Text from the schema is escaped, and the expansion of a schema is bounded (500 rows per table, cycles shown as one row). There is no API reference: the OpenAPI contract is the external documentation of the API (served by `openapi`), and a viewer is the wiring of the user (OQ-141, owner decision of 2026-11-17). The generation of the documentation of a project is `hecate.doc.generate_project_documentation` (see "Documentation of a project"); it is not a function of this module. |
| `licenses` (`hecate.doc.licenses`) | `read(fs, { tree, roots?, max_rocks? })`: the installed rocks of a tree (`<tree>/lib/luarocks/rocks-<lua>/<rock>/<version>/`), read through `fs`, as `{ rocks, problems }` (name, version, declared licence, `required_by`, licence text); `parse_rockspec(text)`: the data of a rockspec without running it; `bundled({ diagrams, theme_fs?, theme_directory? })`: what the generated site bundles, with the licence texts of the theme; `markdown(model, header, bundled?)`: the page. |

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

### Audiences

Documentation has two audiences: *user documentation* (build, run and operate an application on the public
API) and *maintainer documentation* (change Hecate or the project itself: architecture, ADRs, internals, CI and
release, the reference of `*.internal` modules). The generated site is the project team's own documentation, and it
publishes only what it is asked to (OQ-144, [documentation.md](../../docs/architecture/documentation.md)).

| Where | Key | Meaning |
|---|---|---|
| front matter | `audience` | `user` or `maintainer`; anything else is a `BuildError` naming the file. |
| site configuration | `default_audience` | Audience of a page without the key (default `maintainer`). |
| site configuration | `audiences` | Audiences published (default `{ "maintainer" }`, for `hecate.doc.build` and `hecate.doc.generate_project_documentation`). The Hecate website asks for both. |
| site configuration | `audience_sites` | `separate` (default) or `merged`: how several published audiences are written (see below). The Hecate website sets `merged` until its restructure. |

By default `hecate.doc` serves the maintainers of a project (owner decision of 2026-11-18): a page without the key is
maintainer documentation and only `maintainer` is published, so a project that labels nothing publishes everything it
has. A site for the users is a request (`audiences = { "user" }`, with pages labelled `user` or `default_audience =
"user"`).

With several audiences published and `audience_sites = "separate"`, the build writes **one complete site per audience**
below `<out>/<audience>/` (`user/`, `maintainer/`, in the order of `audiences`): its own pages, navigation, search index,
sitemap, `llms.txt`, theme files and `404.html` (the files of `public/` are copied into each), and no page of another
audience; the base URL of each is `<base><audience>/`. `<out>/` holds only the marker file and a redirect to the first
audience. Each site needs its own home page (`index.md` of its audience). With one audience published (or
`audience_sites = "merged"`, which writes one combined site) the layout stays `<out>/`, so URLs do not change when a
project later asks for a second audience. `BuildReport.sites` lists each site and its problems.

A page of an audience that is not published is absent from the pages, the navigation, the search index, the
sitemap and the previous and next links, and a link to it is reported like a broken link (an error with `strict`).
The configuration reference is a `maintainer` page; the code reference lists public symbols, and the pages of
`*.internal` modules and of `private` or `package` classes are `maintainer` pages, generated only when `audiences`
includes `maintainer`. Members that are not public are never listed. When one audience is published, `generate_project_documentation` puts the whole code reference in that site, every page labelled with it (the default maintainer site holds the public symbols too); with both audiences, public symbols are `user` pages and internals `maintainer` pages. Limits: images next to a hidden page are still
copied; the LuaLS export gives the visibility of classes and members, but a project module path is matched against the
`hecate.<name>` prefix of the reference generator (a project namespace other than `hecate.<name>` is not documented yet).

### Documentation of a project

```lua
local doc = require("hecate.doc")
-- Inside a reactor, from the root of a project laid out as `hecate new` does:
doc.generate_project_documentation({ application = application, package_name = "shop" })
```

`hecate.doc.generate_project_documentation(options?)` writes the generated pages (configuration reference from the
application, licences page, code reference) and the guides given as text into the guides directory, then builds
the site (it is not the plain builder `hecate.doc.build`, which only turns a content tree into a site). Every
path option has a default of the conventional layout of a project, relative to `project_dir`; a name that ends in
`_dir` is a directory and a name that ends in `_path` a file. The conventional layout of `developer-experience.md`
(`src/`, `config/`, `tests/`, `lua_modules/`) says nothing about documentation: `docs/` and `docs/dist` are the
conservative choice, as in `examples/hello`, to be confirmed by the owner (OQ-143).

| Option | Default | Meaning |
|---|---|---|
| `project_dir` | `.` | Directory of the project; relative paths below are relative to it, and LuaLS reads its `.luarc.json`. |
| `guides_dir` | `docs` | Content root of the site: `<guides_dir>/<locale>/*.md`, `public/`, `site.lua`. Generated pages are written into it. |
| `output_dir` | `docs/dist` | Where the static site is written. |
| `site_configuration` | none | The site configuration as a table (wins over the file). |
| `site_configuration_path` | `<guides_dir>/site.lua` | The Lua file that returns the site configuration (title, audiences, locales, theme). A missing file is a `BuildError`. |
| `application` | none | The application (`hecate.kernel.Application`, duck-typed on `configuration_schema()`). It is the single source of the configuration reference and of the secrets whose defaults are redacted; without it there is no configuration reference. |
| `package_name` | none | Lua package name of the project (`shop`): asks for the code reference `reference/<package_name>/`. |
| `sources_dir` | `src` | The Lua sources the code reference documents, relative to `project_dir`. |
| `language_server_path`, `language_server_config_path` | found on the path, `<project_dir>/.luarc.json` | The LuaLS executable and its configuration. LuaLS runs the plugin that the configuration declares: the project must be trusted (OQ-142). |
| `licenses_page` | off | `true`, or `{ rocks_tree_dir = "lua_modules", root_rocks, audience, include_bundled }` (see below). |
| `guide_texts` | none | Guides given as text, path below the locale directory to Markdown. |
| `content_locale` | default locale of the site | Locale directory the generated pages and `guide_texts` are written to. |
| `file_system` | `SystemFileSystem` | Where the project is read and the site written (the real one must run inside a reactor). |
| `clean_output_dir`, `fail_on_problems` | `false` | Empty `output_dir` first (only if a previous build wrote it); raise a `BuildError` when the report has problems. |
| `last_updated`, `theme_file_system`, `theme_files_dir` | none | As the options of `build` (`last_updated`, `theme_fs`, `theme_directory`). |

Everything is checked before anything is written: a guide that would overwrite a generated page, or a generated page
that would overwrite a file that is not generated, raises `BuildError` and leaves the tree untouched; generated
pages that a build no longer produces are removed; a wrong option raises `ArgumentError` naming it. There is no
option for a hand-passed configuration schema or for a list of secrets: the application is the single source, and a
schema marks a secret with `writeOnly` or `format: "password"`. The command `hecate doc build` and the section `doc`
of `hecate.project.lua` (same options, filled with these defaults by `hecate new`) are the `cli` item of the roadmap.

### Third-party licences page

`generate_project_documentation` generates `third-party-licences.md` when asked (`licenses_page = true`, which reads
the tree `lua_modules` of the project, or `licenses_page = { rocks_tree_dir = "lua_modules", root_rocks = { "my-app" },
audience = "maintainer", include_bundled = true }`; off by default). The page
is a `maintainer` page unless `audience = "user"` (OQ-144) and lists:

- the rocks of the installed tree: name, version, licence as the rockspec declares it (`description.license`, an SPDX
  identifier when the rock uses one), the rocks that require it, and the licence text found in the installed rock
  (`LICENSE`, `LICENCE`, `COPYING` or `UNLICENSE`, in the rock directory or its `doc` directory), each distinct text
  once. With `root_rocks`, only those rocks and their dependencies, resolved transitively by name over every installed
  version; without it, every installed rock. A dependency that is not installed, an unreadable rockspec, a text that is
  not UTF-8 or larger than 64 KiB, and more than 2000 rocks are problems of the report, never errors;
- what the generated site bundles, with the licence texts reproduced from the files of the theme: STIX Two Text, Fira
  Sans and Fira Code (OFL-1.1), the Hecate brand marks and the Octicons mark (MIT), Mermaid (MIT, with the licences of
  its components named) when a guide holds a `mermaid` block (`include_bundled = false` leaves this section out). The Rust crates
  of the native module (comrak, syntect, two-face) are named as build tools; their texts ship with the release artefacts
  of the native module and are not reproduced (THIRD_PARTY_NOTICES, section 5). No syntax-highlighting colour theme is
  bundled: the highlight colours are the own CSS properties of the theme.

The rocks are files read through `options.file_system`: no `luarocks` process runs. A rockspec is Lua but its content is data,
and it is never executed as code: `hecate.doc.licenses.parse_rockspec` refuses a rockspec that, outside strings and
comments, holds a call (`(` or `:`), a loop, a `goto` or a loader, and evaluates the rest with an empty environment and an
instruction limit. Links in the tree are not followed. Not generated for the Hecate website: its rocks are not an
installed tree (the website lists the same material in `THIRD_PARTY_NOTICES`).

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
(git-ignored); the output is deterministic. Documented packages: `core`, `reactor`, `net`, `json`, `log`, `http`, `router`, `schema`, `openapi`, `container`, `config`, `kernel` (`reference_site.DEFAULT_PACKAGES`).

### Content

`<source>/<locale>/` holds Markdown pages with front matter; `<source>/public/` is copied to
the site root (hidden files excepted). A file of `public/` that has the path of a generated file (a page, `404.html`, `index.html`, `sitemap.xml`, `assets/...`) is a `BuildError`: generated files are never overwritten, and never overwrite hand-made ones silently. Page paths are percent-encoded in URLs (RFC 3986), files keep their real names on disk. `en` is the default locale; a page missing in another locale is built from the
default locale with a visible notice. Page ids are compared in NFC through `hecate.unicode` (every script, ADR 0032), so `cafe` + U+0301 and U+00E9 are one page whatever the file system that authored the tree; links are normalised the same way. The page title is the single `#` heading of the body; front matter `title` is an optional
override of the label used in navigation, search and `<title>` (OQ-35). Front matter keys: `title`, `description`, `order`
(sidebar order), `hecate` and `lua` (the "written for" line), `layout: home` with
`actions: ["Text | page or URL | primary"]`, `outline: false`, `sidebar: false`,
`last_updated`, `source_revision`, `source` (generated pages: repository path of the Lua file). Callouts are GFM alerts: `> [!NOTE|TIP|IMPORTANT|WARNING|CAUTION] [title]`. Raw HTML
is not supported (shown as text, comments are dropped). Conventions: OQ-35. Site configuration (`site.lua`):
`title`, `description`, `base`, `url`, `default_locale`, `locales`, `nav`, `sidebar`,
`repository`, `logo` (a file of `public/`, or `{ light, dark }`, shown as it is and never recoloured; a path without `.`, `..` or hidden segments, and a file missing from `public/` fails the build before anything is written), `favicon` (a file of `public/`, `.svg`, `.png` or `.ico`, or `{ light, dark }` announced with `prefers-color-scheme` media queries; same path checks as `logo`; default: the Hecate adaptive favicon), `sidebar_marker` (boolean, default false: the accent bar at the left of the current sidebar page is opt-in; otherwise a stronger weight and a tint), `theme` (a `.css` file of `public/` loaded after the theme to override its custom properties: colours in light and dark, highlighting, fonts, radii, spacing, sidebar width, with its own `@font-face` for font files of `public/`; OQ-38; the reference page "Theme tokens" lists them), `llms` (boolean, default false: writes `llms.txt` and `llms-full.txt` for the published pages of the default locale, see "llms.txt" below), `edit_link`, `source_edit_link` (edit link of generated pages, from their `source`),
`footer`, `outline`, `strings`, `exclude`; see
`hecate.doc.SiteConfig` and [website/site.lua](../../website/site.lua).

`bin/build.lua` parses its command line strictly: an unknown option, an option without value, a repeated option or a second source directory is a usage error (exit code 2); `--flag=value` is accepted; `--base` and `--url` are validated like the configuration keys.

### Native module and the specification examples

Nesting limit: a native stack overflow cannot be caught, so the module refuses a line that opens more than 100 block containers (`MAX_NESTING` in `native/src/lib.rs`, the list depth that comrak caps itself) before parsing; real documentation rarely nests beyond five levels. The scan reads the leading `>` and list markers of each line and ignores code fences, so it is conservative. Parsing, formatting and the extraction of plain text are iterative, so inline nesting (emphasis, links, images) has no limit; `tests/unit/markdown_nesting_test.lua` runs the pathological inputs in a child process.

The shipped native module exports `render` and `highlight` only (safe mode). The unsafe renderer that runs the CommonMark and GFM specification examples (OQ-37) is compiled only with the cargo feature `spec-tests`: `cargo build --release --features spec-tests --target-dir target/spec` in `native/` (or point `HECATE_DOC_SPEC_LIB` at the library); without that build `commonmark_spec_test.lua` skips.

### Theme

One stylesheet built on the brand-kit tokens (light and dark, system preference plus a
toggle), small vanilla JavaScript (theme toggle, menus, copy buttons, outline highlighting,
search dialog), STIX Two Text / Fira Sans / Fira Code, header with logo, section links,
search, locale switch, theme toggle and repository link, sidebar, "On this page" outline,
previous/next cards, edit link, last updated, callouts, responsive down to 390 px. Pages are
readable without JavaScript. Vendored material: [THIRD_PARTY_NOTICES](../../THIRD_PARTY_NOTICES).

### llms.txt

With `llms = true` in the site configuration, `build` also writes `llms.txt` and `llms-full.txt` at the root of the site
(llmstxt.org; off by default, so no project publishes them unasked). `llms.txt`: `# title`, `> description`, a list of
the pages at the root of the site, then one `##` section per top-level section (navigation order, then by name) with
one `- [title](url): description` line per page, the description being the front matter `description` collapsed to one
line, in the reading order of the sidebar. `llms-full.txt`: the Markdown of the same pages, without front matter, each
after `---` and a `Source: <url>` line (a page without a `#` heading in its body gets one from its title); links between
pages are kept as written. Only published pages (audiences, OQ-144) and the default locale appear; URLs are absolute
when `url` is set. A file of `public/` named `llms.txt` or `llms-full.txt` fails the build when the key is on and is
copied as it is when it is off. Output is deterministic. The repository `llms.txt` stays curated by hand.

### Diagrams

A fenced block with the info string `mermaid` renders as a code block, and `markdown.render` sets `diagrams` on its
result (the page flag `Page.diagrams`). A page with the flag loads, after `theme.js`, the vendored `mermaid.min.js`
(Mermaid 12.3.0, MIT, no CDN) and `mermaid-init.js`, which draws every such block as an SVG in the reader's browser
and hides the code block; the files are written to the output only when a page needs them. Without JavaScript, or when
a diagram cannot be drawn (a notice appears), the source stays readable. The initialiser runs Mermaid with
`securityLevel: "strict"` and SVG labels, locks the theme against `%%{init}%%` directives, takes every colour from the
theme's custom properties (brand tokens) and draws again when the colour theme changes. A page with a diagram
needs `style-src 'unsafe-inline'` under a Content Security Policy; `script-src 'self'` is enough. Decision and update
procedure: [ADR 0033](../../docs/adr/0033-vendored-browser-libraries.md) (`Proposed`).

Manual check (not in CI; Chromium and Playwright): build a small site whose page holds a flowchart, a sequence diagram,
a diagram with `%%{init: {"securityLevel": "loose", "theme": "dark"}}%%` and a malformed block
(`lua packages/doc/bin/build.lua <source> --out <out> --no-git-dates`), serve `<out>` on `127.0.0.1`, open the page
with `colorScheme` light and dark at `deviceScaleFactor` 1, click the theme toggle, and check that: every valid block
is an SVG in the brand colours with no shadow, the directive changed nothing, the malformed block is a code block
after a notice, a page without a diagram requests nothing named `mermaid`, and the request log holds no address outside
the origin (13 requests on the check of 2026-11-17).

### Limits of the current implementation

Not implemented: translations of generated pages keyed by symbol, `llms.txt` for locales other than the default,
versioned documentation, development server, runnable examples, translation status report,
template overrides of the theme (not planned until users ask, OQ-38). Markdown is GFM through comrak; the CommonMark 0.31.2 and GFM extension examples run as a test through the module (OQ-37). The search ranking is client-side JavaScript without an automated test (OQ-36).
Verified on Linux; macOS and Windows are verified by CI only (the shell calls of
`SystemFileSystem` are the platform-specific part, OQ-33).

## Layout

```text
src/hecate/doc/init.lua        public entry point
src/hecate/doc/markdown.lua    Markdown (comrak) and highlight.lua (syntect) over the native module
native/                        the Rust crate (comrak, syntect, two-face; `lua tools/run.lua build-native doc`)
src/hecate/doc/site.lua        content tree, locales, links, navigation, output
src/hecate/doc/reference.lua   code reference pages from the LuaLS export; reference_site.lua, luals.lua
src/hecate/doc/project.lua     page generators for a project: configuration reference, meta files
src/hecate/doc/internal/       page_id.lua (portable and NFC page ids), html.lua, generated_page.lua (notice and front
                               matter of generated pages), project_documentation.lua (`generate_project_documentation`)
src/hecate/doc/theme/          templates (layout.lua), strings, assets/ (css, js, fonts, brand)
bin/build.lua                  build runner (`--reference` generates the code reference first)
bin/reference.lua              code reference runner (used by `tools/run.lua gen-reference`)
tests/unit/  tests/integration/  tests/fixtures/ (fixture site, golden Markdown, brand tokens, fixture package, its LuaLS export and golden reference pages)
```
