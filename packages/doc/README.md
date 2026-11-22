# `hecate-doc`

> Documentation generator and static site builder with an MDN-like theme: guides in Markdown, code reference from LuaLS annotations, configuration reference, locales, search.

| | |
|---|---|
| Module | `hecate.doc` |
| Rock | `hecate-doc` |
| Layer | Tooling |
| Roadmap phase | 3 |
| Status | alpha. The roadmap phase stays 3 because the package is still in progress for it. Implemented: Markdown (comrak) and highlighting (syntect) through the native module, the site model (locales with fallback, sidebar, previous and next), the original theme and its extension points, the search index, `build`, the code reference from LuaLS, the documentation of a project (`generate_project_documentation`: configuration reference, licences page, LuaLS meta files), audiences (one content tree and one documentation site each, built from `<guides_dir>/<audience>/`), Mermaid diagrams (vendored), and `llms.txt` and `llms-full.txt` (opt-in). Pending (Phase 3): versioned documentation, development server, runnable examples, the `hecate doc build` command and the prebuilt binary rocks of the native module |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`reactor`](../reactor), [`json`](../json), [`unicode`](../unicode) |
| Used by | `cli` |
| Native code | Rust (`native/`): comrak (Markdown) and syntect with two-face (highlighting), through `mlua` (ADR 0022) |
| Specification | [documentation.md](../../docs/architecture/documentation.md) |
| Decisions | [ADR 0012](../../docs/adr/0012-website-generator.md), [ADR 0013](../../docs/adr/0013-english-code-multilingual-documentation.md), [ADR 0022](../../docs/adr/0022-doc-dependencies.md), [ADR 0032](../../docs/adr/0032-unicode-normalisation-packages.md), [ADR 0033](../../docs/adr/0033-vendored-browser-libraries.md) |
| Agent | [`pkg-doc`](../../.claude/agents/pkg-doc.md) |
| Repository | read-only mirror `hecate-framework/hecate-doc`, generated from this directory (ADR 0017) |

## Responsibilities

- consume the `lua-language-server --doc` JSON export (the code reference) and the JSON Schema of an application's configuration (the configuration reference)
- render Markdown guides (CommonMark + front matter) and generated reference pages with one MDN-like theme (page template in documentation.md)
- locales with fallback and translation status (`source_revision`)
- static search index
- versioned documentation per minor release
- runnable examples for pure-Lua packages if Lua 5.5 builds to WebAssembly (OQ-11)
- `hecate doc build|serve` for user projects with the same theme, with a base URL option for GitHub Pages project sites
- `llms.txt` and `llms-full.txt` generation (site configuration `generate_llms_txt`, off by default)
- stable anchors per symbol

## Non-goals

- a general-purpose CMS
- an HTTP API reference: the OpenAPI contract is the external documentation of the HTTP API, and any viewer is the user's own wiring (not to be confused with the Lua code reference, which `doc` generates from the annotations of `package_name`)

## Standards and references

- Diátaxis
- OpenAPI 3.1
- CommonMark

## Public API

The entry points are fields of `require("hecate.doc")` (`build`, `generate_project_documentation`, `load_site_configuration`, `normalise_site_configuration`, `Site`, `Page`, the file systems and `BuildError`); the other names below are submodules, loaded with `require("hecate.doc.<name>")` (`markdown`, `front_matter`, `luals`, `highlight`, `navigation`, `search`, `theme`, `reference`, `reference_site`, `project`, `licences`). Direction recorded by the owner on 2026-10-13
(ADR 0012, Accepted): `hecate.doc` is our own static site generator with a
VitePress-like presentation and the Hecate brand kit. Same day, the owner asked for
third-party dependencies wherever they save time (complete GFM, highlighting for many
languages, no new JavaScript development tool); ADR 0022 (Accepted) lists them; the
measurements are in [spike OQ-39](../../docs/spikes/OQ-39-doc-dependencies.md) and
decided in [ADR 0022](../../docs/adr/0022-doc-dependencies.md).

| Name | Description |
|---|---|
| `build(options)` | Reads `<guides_dir>/<locale>/**/*.md`, renders every page of every locale, writes pages, search indexes, theme files and static files to `options.output_dir`, returns a `BuildReport` (`files`, `bytes`, `locales`, `problems`). It builds ONE site from ONE content tree; `build.prepare(options)` does the first half (it loads the tree and returns `{ site, write }`, nothing is written before `write()`), which `generate_project_documentation` uses to load every audience tree before it writes any. Options: `site_configuration`, `guides_dir`, `output_dir`, `file_system`, `clean_output_dir`, `fail_on_problems`, `last_updated`, `theme_file_system`, `theme_files_dir` (an option that is not on this list, or an `output_dir` that is or holds `guides_dir`, raises `ArgumentError` with `context.argument`; no output file is written through a symbolic link). `BuildReport.locales[code]` has `pages` and `fallbacks`. The front matter key `audience` is refused (`BuildError` naming the file and the new layout: see "Audiences"). Output is deterministic. |
| `generate_project_documentation(options?)` | The documentation of a Hecate project: writes the generated pages (configuration reference, licences page, code reference) into the audience trees of the guides directory (`<guides_dir>/<audience>/<locale>/`), then builds each tree listed in `audiences` (default `{ "maintainer" }`) into its own site, `<output_dir>/<audience>/`. Every option has a default of the conventional layout (see "Documentation of a project"); returns a `ProjectDocumentationReport` (a `BuildReport` that adds up the sites, plus `sites`, one entry per tree built, and `code`). Unlike `build`, which only turns one content tree into one site. |
| `load_site_configuration(file_system, path)` | Loads a `site.lua`: it runs with an empty environment, in a coroutine with a limit of instructions and of memory growth. It is the project's own code, not a sandbox against a hostile file (the methods of strings stay reachable). |
| `normalise_site_configuration(raw)` | Validates every key of a site configuration (type and shape; `base_path` must be an absolute path and not protocol-relative, `site_origin` an http(s) origin) and fills the defaults; raises `core.ConfigurationError` with `context.field` naming the offending key. |
| `Site(options)` | The site model (options `site_configuration`, `guides_dir`, `file_system`, `last_updated`, `theme_file_system`, `theme_files_dir`; `Site.LIMITS` holds the depth (32) and entry (100,000) limits of the walks; the normalised configuration is `site.site_configuration`): `load()`, `pages(locale)`, `page(locale, id)`, `emit(write)`, `problems`. |
| `Page` | One page in one locale: `id`, `url`, `title`, `html`, `headings`, `sections`, `fallback`, `meta`. |
| `FileSystem` | Interface (`read`, `write`, `list`, `exists`, `remove_tree`; optional `is_link`) the builder reads and writes through. `list` reports for each entry `is_directory` (what it points to) and `is_link` (the entry is itself a symbolic link, or a Windows junction): the walks of the content tree skip every link with a problem. `remove_tree` unlinks a symbolic link at its path, never its target; `build` with `clean_output_dir` refuses an output directory that is a symbolic link. |
| `MemoryFileSystem(files?)` | In-memory implementation (tests, embedders); `link(path, target)` models a symbolic link (followed by `read`, `write`, `list`; unlinked by `remove_tree`). |
| `SystemFileSystem()` | Real file system over `hecate.reactor.fs`; every method suspends, so call it inside `reactor.run` (OQ-33). `write` refuses a symbolic link at its target; `remove_tree` refuses the roots of a file system (`/`, `C:/`, `//server/share`), `.`, `..`, `~` and paths that normalise to them. On Windows `\` is a separator. |
| `BuildError` | `hecate.doc.BuildError` (a `core.Error`): malformed front matter, unreadable source, clashing URLs, problems with `fail_on_problems`, a file system failure (`SystemFileSystem`), a failed LuaLS export, a page that is not valid UTF-8, a page id that is not a valid file name on Windows (`? : * " < > \| \` and control characters, a trailing dot or space, the device names `CON`, `PRN`, `AUX`, `NUL`, `COM1` to `COM9`, `LPT1` to `LPT9`, `CONIN$`, `CONOUT$`, `CLOCK$` in any case and with an extension; only page ids are checked, not the names of other files of the tree or of `public/`), two pages whose ids differ only by case, two files whose ids differ only in Unicode normalisation (NFC and NFD), a file of `public/` that collides with a generated file, two output files whose paths differ only by case (one file on macOS and Windows). |
| `markdown.render(source, options?)` | Markdown to HTML (`html`, `title`, `headings`, `sections`, `links`); safe mode only (raw HTML is not passed through); a source that is not valid UTF-8 (the message gives the byte position), larger than `markdown.MAX_INPUT_BYTES` (8 MiB), in which a line opens more than `markdown.MAX_NESTING` (100) block containers (`>` quotes and list items; the nesting limit), or whose HTML would exceed the output limit (see Limits), raises `core.ArgumentError` (the message names the limit, and the file when `options.file` is given). `markdown.MAX_INPUT_BYTES`, `MAX_NESTING`, `MAX_OUTPUT_BYTES` and `MAX_OUTPUT_RATIO` expose the limits. |
| `front_matter.parse(source, path?)` | Splits front matter (flat YAML subset) from the body; double-quoted scalars accept only the escapes `\\`, `\"`, `\n`, `\t` (any other backslash sequence is a `BuildError`). |
| `luals` (`hecate.doc.luals`) | `locate()`, `version(language_server_path)`, `export(language_server_path, sources_dir, { file_system, language_server_config_path? })` (output in a private directory removed afterwards: `mktemp -d` on POSIX; on Windows a new directory below `TEMP`/`TMP` with an unpredictable name, never reused if it exists: `windows_temporary_directory(getenv, parts)`, `claim_directory(fs, path)`), `command_line(...)` and `quote(path, windows?)` (pure; shell quoting for POSIX and `cmd.exe`), `excerpt(output)` (the first lines of a failed run, used in the `BuildError`), `PINNED`. `export` runs LuaLS, which runs arbitrary code (see "Trust the documented sources"): document trusted sources only. |
| `highlight.render(language, code)` | Syntax highlighting by syntect (two-face syntaxes, `hl-` classes); an unknown language is escaped and left plain. |
| `navigation` | `sidebar`, `reading_order`, `neighbours`, `top_links`, `section_of` (pure functions). |
| `search.build(locale, pages)`, `search.encode(index)` | The client-side search index. |
| `theme` | `page(context)`, `not_found(context)`, `strings`, `asset_files`, `diagram_files` (written only when a page holds a diagram), `assets_directory()`. |
| `reference` (`hecate.doc.reference`) | `generate(inputs, options)`: pages of the code reference from LuaLS exports (pure; option `pages_dir`, the directory of the pages below the locale root, default `reference`; option `internal` adds the pages of `*.internal` modules and of non-public classes; `split_audiences` limits links and the module page to the audience of the page; the result lists the audience of each page in `audiences`, `maintainer` for those internals and `user` for the rest); `is_generated(text)` (the one test of `internal.generated_page`: `generated: true` or the notice as the first line after the front matter); `GENERATED` (the marker). |
| `reference_site` (`hecate.doc.reference_site`) | `run(options)`: runs LuaLS on the packages, generates and writes the pages (skips with `report.skipped` without LuaLS). Options: `project_dir`, `locale_dir` (the locale directory of the guides the pages are written into, such as `website/en`), `file_system`, `packages`, `language_server_path`, `language_server_config_path`, `audience_locale_dirs` (`{ user = dir, maintainer = dir }`, instead of `locale_dir`: public pages into the first, internals into the second, links never crossing), `sources_dir_pattern` (a `string.format` pattern of the sources directory of a package below `project_dir`, default `packages/%s/src`), `since`, `internal`; `write(file_system, locale_dir, result, packages, audience?)` (with `audience`, only the pages of that audience); `DEFAULT_PACKAGES`. |
| `project` (`hecate.doc.project`) | `configuration_page(schema)`: the configuration reference from a JSON Schema, a page for the `maintainer` tree that prints `[redacted]` for the default of a secret key or of any row that holds one (`writeOnly: true` or `format: "password"` on the row or on any subschema reachable from it, or on an object above it); `meta(schemas, namespace)`: a LuaLS `---@meta` declaration file (classes, aliases) from named JSON Schemas; `is_generated(text)`. Text from the schema is escaped, and the expansion of a schema is bounded (500 rows per table, cycles shown as one row). There is no HTTP API reference: the OpenAPI contract is the external documentation of the HTTP API (served by `openapi`), and a viewer is the wiring of the user (owner decision of 2026-11-17). The code reference is a different thing. The generation of the documentation of a project is `hecate.doc.generate_project_documentation` (see "Documentation of a project"); it is not a function of this module. |
| `licences` (`hecate.doc.licences`) | `read(file_system, { rocks_tree_dir, root_rocks?, max_rocks? })`: the installed rocks of a tree (`<rocks_tree_dir>/lib/luarocks/rocks-<lua>/<rock>/<version>/`), read through `file_system`, as `{ rocks, problems }` (name, version, `licence` as declared, `required_by`, licence text); `parse_rockspec(text)`: the data of a rockspec without running it; `bundled({ diagrams, theme_file_system?, theme_files_dir? })`: what the generated site bundles, with the licence texts of the theme; `markdown(model, header, bundled?)`: the page. |

### Building a site

```sh
lua packages/doc/bin/build.lua website/user --config website/site.lua --strict          # writes website/dist (git-ignored)
lua packages/doc/bin/build.lua website/user --config website/site.lua --out /tmp/site --base /hecate/ --clean
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
release, the reference of `*.internal` modules). They are **two different websites** (owner decision of 2026-11-21,
OQ-144): two content trees in the sources, two directories in the output, and no page that belongs to both
([documentation.md](../../docs/architecture/documentation.md)). `hecate.doc` serves the maintainers of a project
first (owner decision of 2026-11-18): the default builds the `maintainer` tree only.

```text
docs/
  site.lua                 the site configuration: one file for the project, shared by every audience site
  user/                    the content tree of the user site (optional)
    en/index.md            its home page, and its other pages and files, per locale
    fr/...
    public/                its own static files (copied to the root of the user site)
  maintainer/              the content tree of the maintainer site
    en/index.md
    public/
  dist/                    the output (default)
    user/                  the user site: pages, navigation, search index, sitemap, llms.txt, 404, theme files
    maintainer/            the maintainer site
```

A tree is laid out exactly like the tree of a plain site (`build.build`): `<guides_dir>/<audience>/<locale>/**/*.md`,
and `public/` and the files next to the pages **inside the tree**, next to the locale directories (decision: `public/`
is a part of the tree, so a tree can be moved, built or deleted whole, and the two sites never share a static file).
Each tree is built by the plain builder into `<output_dir>/<audience>/`, with its own pages, navigation, search index,
sitemap, `llms.txt`, theme files and `404.html`, and its base path is `<base_path><audience>/`. `<output_dir>/` holds
only the marker file and a redirect to the first site built. There is no `audience` front matter key (a page that still
carries it is a `BuildError` naming the file and the layout), no `default_audience`, `audience_sites` or `audiences` in
`site.lua` (`ConfigurationError` saying what replaced them, `internal.renamed_options`) and no merged site: the
audience of a page is the tree it lies in.

| Where | Name | Meaning |
|---|---|---|
| option of `generate_project_documentation` | `audiences` | The trees to build, `user` and `maintainer` (default `{ "maintainer" }`). A tree that is not listed is not built and is no error; a listed tree that does not exist is a problem (`add docs/user/en/index.md`). |
| `<guides_dir>/<audience>/` | content tree | One tree per audience; each needs its own home page (`index.md` of the default locale), and its absence is a problem of that tree. |
| `<guides_dir>/site.lua` | site configuration | One file: title, locales, theme and the other keys apply to every audience site. Per-audience overrides are out of scope. |

Generated pages go to the right tree: the configuration reference and the licences page into the `maintainer` tree (the
licences page into another listed tree with `licences_page.audience`), the code reference into the `user` tree (public
symbols) and the `maintainer` tree (the pages of `*.internal` modules and of `private` or `package` classes, only when
`maintainer` is built). When only one tree is built, the whole code reference goes into it (the internals only for the
`maintainer` tree). With both, the pages of one tree never link to the other and the module page lists only the classes
of its own tree. Members that are not public are never listed. A project namespace other than `hecate.<name>` is not
documented yet (the LuaLS export gives the visibility of classes and members, and the module path is matched against
the `hecate.<name>` prefix of the reference generator).

**Links between the two sites.** The builder cannot check a link from one site to the other: it is an ordinary link.
Write an absolute URL (`https://example.org/user/en/guide/`), or a relative one: the browser reads a relative link from
the URL of the page, not from its source file: with the base path `/maintainer/`, `guide/a.md` is served at
`/maintainer/en/guide/a/`, so the user page `guide/` is `../../../../user/en/guide/` (one `..` per segment of that URL).
The builder leaves
a relative link that climbs two levels or more above the locale directory (out of the tree) as written and reports no
problem; a link that climbs to the content root only (`../x.md`) stays a problem, as does a broken link inside the tree.
An absolute path (`/user/en/guide/`) is not the way: it is prefixed with the base path of its own site.

### Documentation of a project

```lua
local doc = require("hecate.doc")
-- Inside a reactor, from the root of a project laid out as `hecate new` does:
doc.generate_project_documentation({ application = application, package_name = "shop" })
```

`hecate.doc.generate_project_documentation(options?)` writes the generated pages (configuration reference from the
application, licences page, code reference) into the audience trees of the guides directory, then builds each
tree listed in `audiences` into its own site (it is not the plain builder `hecate.doc.build`, which only turns one
content tree into one site, and which it calls once per tree). Every
path option has a default of the conventional layout of a project, relative to `project_dir`; a name that ends in
`_dir` is a directory and a name that ends in `_path` a file. The conventional layout of `developer-experience.md`
(`src/`, `config/`, `tests/`, `lua_modules/`) says nothing about documentation: `docs/` and `docs/dist` are the
conservative choice, as in `examples/hello`.

| Option | Default | Meaning |
|---|---|---|
| `project_dir` | `.` | Directory of the project; relative paths below are relative to it. |
| `guides_dir` | `docs` | Root of the guides: one content tree per audience, `<guides_dir>/<audience>/<locale>/*.md` and `<guides_dir>/<audience>/public/`, and `site.lua`. Generated pages are written into the trees. |
| `audiences` | `{ "maintainer" }` | The trees to build, `"user"` and `"maintainer"`, each into its own site. A tree that is not listed is not built and is no error; a listed tree that does not exist is a problem (`add docs/user/en/index.md`), and the tree is skipped. |
| `output_dir` | `docs/dist` | Where the sites are written, one per tree: `<output_dir>/<audience>/`, with a marker file and a redirect to the first site at its root. Below `guides_dir` (the default) is allowed; it may not be `guides_dir` or `project_dir`, hold either, or overlap `sources_dir` (`ArgumentError`). |
| `site_configuration` | none | The site configuration as a table, the same for every audience site. Giving it with `site_configuration_path` is an error. |
| `site_configuration_path` | `<guides_dir>/site.lua` | The Lua file that returns the site configuration (title, locales, theme, ...; title, locales and theme apply to every audience site, per-audience overrides are out of scope; the base path of each site is `base_path` plus the audience, and `{path}` of `edit_link_template` is preceded by the audience). A path you give is relative to `project_dir` like every other path; the default is below `guides_dir`. A missing file is a `BuildError` with the cause and the remedies. |
| `application` | none | The application (`hecate.kernel.Application`, duck-typed on `configuration_schema()`). It is the single source of the configuration reference and, through the `writeOnly` marks of its schema, of the secrets whose defaults are redacted; without it there is no configuration reference. |
| `package_name` | none | Lua package name of the project (`shop`): asks for the code reference `reference/<package_name>/`: public symbols into the `user` tree and internals into the `maintainer` tree when both are built, the whole reference into the one tree otherwise. |
| `sources_dir` | `src` | The Lua sources the code reference documents, relative to `project_dir`; never absolute (LuaLS runs the plugins of the configurations of the directory it documents). |
| `language_server_path`, `language_server_config_path` | found on the path, none | The LuaLS executable and the `.luarc.json` passed as `--configpath` (none is passed when unset). LuaLS runs the plugins that the configurations it reaches declare: the project must be trusted (see below). |
| `licences_page` | off | `true`, or `{ rocks_tree_dir = "lua_modules", root_rocks, audience, include_bundled }` (see below; `audience` names the tree, one of the listed `audiences`). |
| `content_locale` | default locale of the site | Locale directory of each tree the generated pages are written to; a locale of the site configuration. |
| `file_system` | `SystemFileSystem` | Where the project is read and the sites written (the real one must run inside a reactor). |
| `clean_output_dir`, `fail_on_problems` | `false` | Empty the whole `output_dir` first (only if a previous build wrote it); raise one `BuildError` that lists every problem (missing tree, builds, licences page, code reference; a problem of a site is prefixed with its audience and "site:", as `user site: ...`), after the sites are written. |
| `last_updated`, `theme_file_system`, `theme_files_dir` | none | As the options of `build`. |

Everything is checked before anything is written: a guide that would overwrite a generated page, or a generated page
that would overwrite a file that is not generated or lies behind a symbolic link, raises `BuildError` and leaves the trees
untouched; every tree is read and rendered before any site is written to the output; generated pages that a build no longer produces are removed; a wrong option, or one that is not on the list
(an old name, a typo), raises `ArgumentError` naming it (`context.argument`) and the replacement of an old name. `\` is a
separator in every path option. A page is *generated* when its front matter says `generated: true` or the first line after
the front matter is the notice `<!-- Generated by hecate.doc. ... -->`: a guide that quotes the notice is never touched. There is no
option for a hand-passed configuration schema or for a list of secrets: the application is the single source, and a
schema marks a secret with `writeOnly` or `format: "password"`. The command `hecate doc build` and the section `doc`
of `hecate.project.lua` (same options, filled with these defaults by `hecate new`) are the `cli` item of the roadmap.

### Trust the documented sources

The code reference runs LuaLS, and **LuaLS runs arbitrary code**. A plugin (`Lua.runtime.plugin`) declared by any LuaLS
configuration reachable from the documented directory is executed with full file and command access, as the user who
runs the build: a `.luarc.json` or `.luarc.jsonc`, a `.vscode/settings.json`, and a `.luarc.json` inside the
documented sources directory, even when `language_server_config_path` points elsewhere (the file given is only the one
passed as `--configpath`; with no `language_server_config_path`, no `--configpath` is passed at all). The executable
`lua-language-server` is found through `PATH` unless `language_server_path` names it, so `PATH` is trusted as well.
Request a code reference (`package_name`) only for a project you control. Until the command `hecate doc build` warns
and lets the user stop (roadmap, item `cli`), the library is silent: it does not warn and does not prompt. A plugin-free
`.luarc.json` in a temporary directory is the answer for a project that you do not control.

### Third-party licences page

`generate_project_documentation` generates `third-party-licences.md` when asked (`licences_page = true`, which reads
the tree `lua_modules` of the project, or `licences_page = { rocks_tree_dir = "lua_modules", root_rocks = { "my-app" },
audience = "maintainer", include_bundled = true }`; off by default). The page
goes into the `maintainer` tree unless `audience` names another listed tree (default `maintainer` when it is built,
otherwise the first tree built) and lists:

- the rocks of the installed tree: name, version, licence as the rockspec declares it (`description.license`, an SPDX
  identifier when the rock uses one), the rocks that require it, and the licence text found in the installed rock
  (`LICENSE`, `LICENCE`, `COPYING` or `UNLICENSE`, in the rock directory or its `doc` directory), each distinct text
  once. With `root_rocks`, only those rocks and their dependencies, resolved transitively by name over every installed
  version; without it, every installed rock. A dependency that is not installed, an unreadable rockspec, a text that is
  not UTF-8 or larger than 64 KiB, and more than 2000 rocks are problems of the report, never errors;
- what the generated site bundles, with the licence texts reproduced from the files of the theme: STIX Two Text, Fira
  Sans and Fira Code (OFL-1.1), the Hecate brand marks and the Octicons mark (MIT), Mermaid (MIT, with the licences of
  its components named) when a guide holds a `mermaid` block (`include_bundled = false` leaves this section out). The Rust crates
  of the native module (comrak, syntect, two-face) are not part of a generated site (they are build tools: the site holds
  their output, not their code) and are not on this page; their licence texts are reproduced for the native module in
  `native/LICENSES-rust.md` (generated by `gen-rust-licences`), which the release artefacts of the native module ship
  (THIRD_PARTY_NOTICES, section 5). No syntax-highlighting colour theme is
  bundled: the highlight colours are the own CSS properties of the theme.

The rocks are files read through `options.file_system`: no `luarocks` process runs. A rockspec is Lua but its content is data,
and it is never executed as code: `hecate.doc.licences.parse_rockspec` refuses a rockspec that, outside strings and
comments, holds a call (`(`, `:`, or a name followed by a string or a table), a concatenation (`..`), a loop, a `goto`
or a loader, and evaluates the rest with an empty environment under a limit of instructions and of memory growth
(`site.lua` runs under the same limits). Links in the tree are not followed. Not generated for the Hecate website: its rocks are not an
installed tree (the website lists the same material in `THIRD_PARTY_NOTICES`).

### Code reference

The reference pages are generated from the JSON export of `lua-language-server --doc` (LuaLS
3.19.1, pinned; owner decision of 2026-10-13: annotate every module table as a `---@class`,
no annotation parser of our own; conventions in
[coding-standards.md](../../docs/architecture/coding-standards.md), "Annotations for the
reference"; choices in OQ-40).

```sh
lua tools/run.lua gen-reference            # writes website/user/en/reference/<package>/, needs lua-language-server
lua tools/run.lua gen-reference --require  # CI: fail instead of skipping when LuaLS is missing
lua packages/doc/bin/build.lua website/user --config website/site.lua --root . --strict --reference   # generate, then build the site
```

One page per package (`index.md`, the module), per class or type (`<Class>.md`) and per function
of the module (`functions/<name>.md`). Every page has the nine sections of the template of
[documentation.md](../../docs/architecture/documentation.md) in order (summary, syntax, parameters
and return values, errors raised, whether it may suspend (`---@async`), examples, specifications,
compatibility, see also), a `generated: true` front matter key and a header comment saying not to
edit it. A class page lists its fields and methods with a stable anchor each (`#name`). Examples
are the tested files `packages/<package>/examples/<symbol>.lua`. The pages are not committed
(git-ignored); the output is deterministic. Documented packages (13): `core`, `reactor`, `net`, `json`, `log`, `http`, `router`, `schema`, `openapi`, `container`, `config`, `kernel`, `test` (`reference_site.DEFAULT_PACKAGES`).

### Content

In this section `<guides_dir>` is the root of ONE content tree, as `build.build` reads it. For a project it is the tree of
an audience, `<guides_dir>/<audience>/` (see "Audiences"); the Hecate website is one such tree, `website/`, until it is
moved into `website/user/` and `website/maintainer/` (a move of directories, OQ-144). `<guides_dir>/<locale>/` holds Markdown pages with front matter; `<guides_dir>/public/` is copied to
the site root (hidden files excepted). A file of `public/` that has the path of a generated file (a page, `404.html`, `index.html`, `sitemap.xml`, `assets/...`) is a `BuildError`: generated files are never overwritten, and never overwrite hand-made ones silently. Page paths are percent-encoded in URLs (RFC 3986), files keep their real names on disk. `en` is the default locale; a page missing in another locale is built from the
default locale with a visible notice. Page ids are compared in NFC through `hecate.unicode` (every script, ADR 0032), so `cafe` + U+0301 and U+00E9 are one page whatever the file system that authored the tree; links are normalised the same way. **Portable names:** every file of the site goes through one check (`internal.portable_name`): pages (ids), the files next to the guides, the files of `public/` and the files `logo_path`, `favicon_path` and `stylesheet_path` name. Each segment must be a valid Windows file name (`aux.png`, `con/x.svg`, `x.`, `a:b` are a `BuildError`), is written in NFC, and has a case-fold key that must be unique over the pages, the files next to the guides (with the fallback files of the default locale) and `public/` together: `Img/a.svg` and `img/a.svg`, `Logo.svg` and `logo.svg`, `Ж.md` and `ж.md` are a `BuildError`, as is a file `a` next to a page `a` (`a/index.html`) or a path that is a file for one source and a directory for another. A configured file must be spelt as the file is (a name that opens only on a case-insensitive system is a broken link elsewhere). The case fold is the Unicode *simple* case folding for Latin, Greek, Cyrillic, Armenian and fullwidth letters, not for every script (OQ-145). Length limits are problems, so errors under `fail_on_problems`: a segment over 255 bytes, and an output path (`<output_dir>/<locale>/<id>/index.html`, as `output_dir` is given: a relative one is not resolved) of 260 characters or more, the Windows `MAX_PATH` with its terminating NUL. The `.md` suffix and `exclude_file_names` are matched without regard to case (`README.MD` is excluded like `README.md`, `Guide.MD` is a page), always: the safe direction on every platform. The page title is the single `#` heading of the body; front matter `title` is an optional
override of the label used in navigation, search and `<title>` (OQ-35). Front matter keys: `title`, `description`, `order`
(sidebar order), `hecate` and `lua` (the "written for" line), `layout: home` with
`actions: ["Text | page or URL | primary"]`, `outline: false`, `sidebar: false`,
`last_updated`, `source_revision`, `source` (generated pages: repository path of the Lua file). Callouts are GFM alerts: `> [!NOTE|TIP|IMPORTANT|WARNING|CAUTION] [title]`. Raw HTML
is not supported (shown as text, comments are dropped). Conventions: OQ-35. Site configuration (`site.lua`):
`title`, `description`, `base_path`, `site_origin`, `default_locale`, `locales`, `top_links`, `sidebar`,
`repository_url`, `logo_path` (a file of `public/`, or `{ light, dark }`, shown as it is and never recoloured; a path without `.`, `..` or hidden segments, and a file missing from `public/` fails the build before anything is written), `favicon_path` (a file of `public/`, `.svg`, `.png` or `.ico`, or `{ light, dark }` announced with `prefers-color-scheme` media queries; same path checks as `logo_path`; default: the Hecate adaptive favicon), `sidebar_marker` (boolean, default false: the accent bar at the left of the current sidebar page is opt-in; otherwise a stronger weight and a tint), `stylesheet_path` (a `.css` file of `public/` loaded after the theme to override its custom properties: colours in light and dark, highlighting, fonts, radii, spacing, sidebar width, with its own `@font-face` for font files of `public/`; OQ-38; the reference page "Theme tokens" lists them), `generate_llms_txt` (boolean, default false: writes `llms.txt` and `llms-full.txt` for the published pages of the default locale, see "llms.txt" below), `edit_link_template`, `source_edit_link_template` (URL templates with `{path}`; the second for generated pages, from their `source`),
`footer`, `outline_levels`, `interface_strings`, `exclude_file_names`; see
`hecate.doc.SiteConfiguration` and [website/site.lua](../../website/site.lua). The vocabulary rule of OQ-143 names every key for what it is (`_path` a file of `public/`, `_template` a URL template, `_levels`, `_names`), with no alias: the old names (`logo`, `favicon`, `theme`, `colors`, `llms`, `base`, `url`, `repository`, `edit_link`, `source_edit_link`, `exclude`, `outline`, `strings`, `nav`) are no longer read, and `src/hecate/doc/internal/renamed_options.lua` records old to new.

`bin/build.lua` parses its command line strictly: an unknown option, an option without value, a repeated option or a second source directory is a usage error (exit code 2); `--flag=value` is accepted; `--base` and `--url` are validated like the configuration keys.

### Native module and the specification examples

Nesting limit: a native stack overflow cannot be caught, so the module refuses a line that opens more than 100 block containers (`MAX_NESTING` in `native/src/lib.rs`, the list depth that comrak caps itself) before parsing; real documentation rarely nests beyond five levels. The scan reads the leading `>` and list markers of each line and ignores code fences, so it is conservative. Parsing, formatting and the extraction of plain text are iterative, so inline nesting (emphasis, links, images) has no limit; `tests/unit/markdown_nesting_test.lua` runs the pathological inputs in a child process.

Size limits (the same in Rust, `native/src/lib.rs`, and Lua): the Markdown given to `markdown.render` (and the code given to `highlight`) is at most 8 MiB (`MAX_INPUT_BYTES`, 8388608 bytes). The HTML a render produces is at most 32 times the Markdown (`MAX_OUTPUT_RATIO`), but never less than 1 MiB (so a short page with a lot of markup is not refused) and never more than 64 MiB (`MAX_OUTPUT_BYTES`); the renderer stops writing as soon as the bound is crossed, so an amplifying document (footnote references multiply their size by about 27 or more) is refused without using the memory. Each refusal is a `core.ArgumentError` that names the limit. The page reader refuses a page larger than 8 MiB with a `BuildError` naming the file. The nesting rule counts container markers in the leading prefix of a line only and ignores code fences: a fenced sample that quotes a line of 101 nested `>` is rejected like any other document, and a line of 100 is accepted. Heading identifiers are numbered in constant amortised time per heading (`tests/unit/markdown_limits_test.lua` renders 20,000 identical headings).

The shipped native module exports `render` and `highlight` only (safe mode). The unsafe renderer that runs the CommonMark and GFM specification examples (OQ-37) is compiled only with the cargo feature `spec-tests`: `cargo build --release --features spec-tests --target-dir target/spec` in `native/` (or point `HECATE_DOC_SPEC_LIB` at the library); without that build `commonmark_spec_test.lua` skips.

### Theme

One stylesheet built on the brand-kit tokens (light and dark, system preference plus a
toggle), small vanilla JavaScript (theme toggle, menus, copy buttons, outline highlighting,
search dialog), STIX Two Text / Fira Sans / Fira Code, header with logo, section links,
search, locale switch, theme toggle and repository link, sidebar, "On this page" outline,
previous/next cards, edit link, last updated, callouts, responsive down to 390 px. Pages are
readable without JavaScript. Vendored material: [THIRD_PARTY_NOTICES](../../THIRD_PARTY_NOTICES).

### llms.txt

With `generate_llms_txt = true` in the site configuration, `build` also writes `llms.txt` and `llms-full.txt` at the root of the site
(llmstxt.org; off by default, so no project publishes them unasked). `llms.txt`: `# title`, `> description`, a list of
the pages at the root of the site, then one `##` section per top-level section (navigation order, then by name) with
one `- [title](url): description` line per page, the description being the front matter `description` collapsed to one
line, in the reading order of the sidebar. `llms-full.txt`: the Markdown of the same pages, without front matter, each
after `---` and a `Source: <url>` line (a page without a `#` heading in its body gets one from its title); links between
pages are kept as written. Only the pages of the tree of the site and the default locale appear; URLs are absolute
when `site_origin` is set. A file of `public/` named `llms.txt` or `llms-full.txt` fails the build when the key is on and is
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
procedure: [ADR 0033](../../docs/adr/0033-vendored-browser-libraries.md) (Accepted).

A drawn diagram has a toolbar at its top right (zoom in, zoom out, reset the view, full screen; real buttons with
names in the interface strings `diagram_*`, in English and French) and can be moved and zoomed without a library
(the code is in `mermaid-init.js`, so it is loaded only on a page with a diagram): drag with the mouse or a finger,
pinch on touch, `Ctrl` or `Cmd` with the wheel (a trackpad pinch arrives as such), and, while the diagram has focus,
`+`, `-`, `0` and the arrow keys. The wheel alone zooms only in full screen, so scrolling the page is never taken.
The view is a scale (0.2 to 10) and a translation applied to the SVG with the CSS `transform`; zoom is centred on the
pointer, the gesture centre or the frame centre, and a part of the diagram always stays in the frame. On touch, a
vertical swipe over a diagram in the page still scrolls the page (`touch-action: pan-y`: a horizontal drag and a pinch
move the diagram); full screen takes every gesture. Full screen uses the Fullscreen API when the browser has it and a
fixed overlay always (iOS Safari has no API for an element), fills the viewport on the `--surface-100` background, shows
a close button, locks the scroll on the root element only (`html.diagram-fullscreen`, never `overflow: hidden` on
`body`), keeps `Tab` inside the overlay, closes on `Esc`, and returns focus to the button that opened it; the view is
fitted on entering, on leaving and on a resize. A redraw for the other colour theme keeps the current zoom and
position. Nothing is animated, so `prefers-reduced-motion` needs no special case. A failed render shows the notice and
no toolbar.

Manual check (not in CI; Chromium and Playwright): build a small site whose page holds a flowchart, a sequence diagram,
a diagram with `%%{init: {"securityLevel": "loose", "theme": "dark"}}%%` and a malformed block
(`lua packages/doc/bin/build.lua <source> --out <out> --no-git-dates`), serve `<out>` on `127.0.0.1`, open the page
with `colorScheme` light and dark at `deviceScaleFactor` 1, click the theme toggle, and check that: every valid block
is an SVG in the brand colours with no shadow, the directive changed nothing, the malformed block is a code block
after a notice, a page without a diagram requests nothing named `mermaid`, and the request log holds no address outside
the origin (13 requests on the check of 2026-11-17).

Navigation check (2026-11-18; Playwright and the Chromium that is installed, `require("playwright")`, no download):
build `lua examples/hello/build_docs.lua`, serve `examples/hello/docs/dist` on `127.0.0.1` with
`Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'`, open
`/en/guide/request-flow/` in each colour scheme, and check on `figure.diagram .diagram-viewport svg`
(`style.transform` is `translate(Xpx, Ypx) scale(S)`): the toolbar holds five buttons with names (the close button is
hidden); zoom in raises `S`, zoom out lowers it, reset gives `translate(0px, 0px) scale(1)`; a mouse drag of
(60, 30) pixels moves `X` and `Y` by that much and sets `is-panning` while the button is down; a wheel event without
`Ctrl` is not cancelled and leaves `S` unchanged, `Ctrl` and the wheel raises `S`; with focus on the viewport `+`, `-`,
`0` and the arrows change the view; the full screen button opens the overlay (`is-fullscreen`,
`document.fullscreenElement` set, `html.diagram-fullscreen`, `overflow: hidden` on `html` and not on `body`), fits the
diagram, `Tab` stays inside, the wheel alone zooms, `Esc` closes it and focus is back on the opener; with
`Element.prototype.requestFullscreen` set to `undefined` the overlay alone opens, follows `setViewportSize` and `Esc`
closes it; the theme toggle keeps `S`, `X` and `Y`; no request leaves the origin and the console is empty. On a
390 by 844 touch context, the overlay fills the viewport, a two-finger `Input.dispatchTouchEvent` pinch raises `S` and a
one-finger drag moves `X`. All of it passed on 2026-11-18 (67 checks); screenshots in light, dark, full screen and 390
pixels were looked at. Firefox is checked the same way with `playwright.firefox` (`npx playwright install firefox`,
which needs the network and was not possible on that machine), and Safari by hand.

Not verified in Firefox or Safari (2026-11-18): the Fullscreen API prefixed path (`webkitRequestFullscreen`,
`webkitfullscreenchange`), Pointer Events with `setPointerCapture` and `touch-action: pan-y` on iOS (a vertical swipe
on a diagram should scroll the page, a horizontal drag and a pinch should move it), the `Ctrl`-wheel path on a Safari
trackpad (Safari sends `gesturechange` rather than a `Ctrl` wheel, so a pinch may not zoom there; the buttons and the
keys do), the Firefox rendering of a scaled SVG, and VoiceOver and NVDA announcements of the toolbar and of the
focusable diagram.

Owner's manual check, 2026-11-21: the four layout fixes and the diagram controls were rechecked by hand in Firefox and Safari, and nothing was found. The list above stays what no automated check covers.

### Limits of the current implementation

Not implemented: translations of generated pages keyed by symbol, `llms.txt` for locales other than the default, a switcher
between the audience sites (a link from one site to the other is an ordinary link, see "Audiences"), per-audience overrides of
`site.lua`,
versioned documentation, development server, runnable examples, translation status report,
template overrides of the theme (not planned until users ask, OQ-38). Markdown is GFM through comrak; the CommonMark 0.31.2 and GFM extension examples run as a test through the module (OQ-37). The search ranking is client-side JavaScript without an automated test (OQ-36).
Verified on Linux; macOS and Windows are verified by CI only (the shell calls of
`SystemFileSystem` are the platform-specific part, OQ-33).

## Layout

```text
src/hecate/doc/init.lua        public entry point
src/hecate/doc/build.lua       `build`: one content tree to one site (`generate_project_documentation` calls it once per audience tree)
src/hecate/doc/config.lua      site configuration: `normalise`, defaults
src/hecate/doc/markdown.lua    Markdown (comrak) and highlight.lua (syntect) over the native module
native/                        the Rust crate (comrak, syntect, two-face; `lua tools/run.lua build-native doc`)
src/hecate/doc/site.lua        content tree, locales, links, navigation, output
src/hecate/doc/reference.lua   code reference pages from the LuaLS export; reference_site.lua, luals.lua
src/hecate/doc/project.lua     page generators for a project: configuration reference, meta files
src/hecate/doc/licences.lua    the third-party licences page: installed rocks read as files, bundled theme material
src/hecate/doc/internal/       page_id.lua (Windows names, NFC), portable_name.lua (`portable_name`, case-fold key, length limits, namespace of output paths), case_fold.lua (simple case folding, OQ-145), html.lua, generated_page.lua (notice and front
                               matter of generated pages), project_documentation.lua (`generate_project_documentation`), text.lua,
                               renamed_options.lua (the old names of the options and site keys, old to new, OQ-143)
src/hecate/doc/theme/          templates (layout.lua), strings, assets/ (css, js, fonts, brand)
bin/build.lua                  build runner (`--reference` generates the code reference first)
bin/reference.lua              code reference runner (used by `tools/run.lua gen-reference`)
tests/unit/  tests/integration/  tests/fixtures/ (fixture site, golden Markdown, brand tokens, fixture package, its LuaLS export and golden reference pages)
```
