---
description: The documentation generator for user projects: the site configuration, the pages generated from the configuration schema, LuaLS meta files, and the theme extension points.
hecate: "0.x"
lua: "5.5"
order: 3
---

<!-- Hand-written reference page (not generated): keep it in step with packages/doc/README.md. -->

# Project documentation

`hecate.doc` builds the documentation site of a user project with the same theme as the hecate website.
This page covers what a project can configure and what is generated for it, for hecate 0.x and Lua 5.5.

## Audiences

The site that `doc.generate_project_documentation` writes is the documentation of the project's own team. By default it
serves the maintainers. There are two audiences: `user` (build, run and operate an application on the public API) and
`maintainer` (change the project itself: architecture, decisions, internals, CI and release). They are two different
websites: one content tree each in the sources, and one output directory each.

```text
docs/
  site.lua                   one site configuration for the project
  user/                      the tree of the user site (optional)
    en/index.md              its home page
    en/guide/getting-started.md
    public/                  its own static files
  maintainer/                the tree of the maintainer site
    en/index.md              its home page
    en/architecture.md
    public/
  dist/                      the output
    user/                    the user site
    maintainer/              the maintainer site
```

Each tree is laid out like a plain site: one directory per locale, and `public/` next to them. It is built by the plain
builder into `<output_dir>/<audience>/`, so each site has its own pages, navigation, search index, sitemap, `llms.txt`,
theme files and `404.html`, and no page of the other tree. The base path of a site is the `base_path` of the
configuration plus the audience. `<output_dir>/` itself holds only a marker file and a redirect to the first site.

| Where | Name | Meaning |
|---|---|---|
| Option of `generate_project_documentation` | `audiences` | The trees to build. Default `{ "maintainer" }`. Ask for `{ "user", "maintainer" }` for both. |
| `<guides_dir>/<audience>/` | content tree | Each tree needs its own home page: `index.md` in the default locale. |
| `<guides_dir>/site.lua` | site configuration | One file. Its title, locales, theme and other keys apply to every audience site; a different title or theme for one audience is not possible. |

A tree that is not listed in `audiences` is not built, and that is not an error. A listed tree that does not exist is a
problem, which fails the build under `fail_on_problems`, and tells you the file to add (`add docs/user/en/index.md`). A
tree without its home page is a problem of that tree.

There is no `audience` key in the front matter: a page that still has it fails the build with a `BuildError` that names
the file and the layout. The site configuration keys `audiences`, `default_audience` and `audience_sites` are gone too, and
`site.lua` refuses them. Move the pages into the tree of their audience and delete the keys.

Generated pages go into the right tree. The configuration reference and the licences page are pages of the `maintainer`
tree (`licences_page.audience` can name another listed tree). The code reference lists public symbols in the `user` tree;
the pages of `*.internal` modules and of `private` or `package` classes go to the `maintainer` tree. When only one tree is
built, it holds the whole code reference. With both trees, a reference page links only to pages of its own tree, and the
module page lists only the classes of its own tree. A field or method that is not public is never listed.

A link from a page of one site to a page of the other site is an ordinary link that the builder cannot check. Write an
absolute URL, `https://example.org/user/en/guide/`, or a relative link. The browser reads a relative link from the URL of
the page, not from its source file: the page `guide/a.md` of a site served at `/maintainer/` is at `/maintainer/en/guide/a/`,
so the user page `guide/` is `../../../../user/en/guide/`. The builder leaves a relative link that climbs two levels or more
above the locale directory as written, and reports no problem. A link that climbs to the content root only (`../x.md`) is
still a problem, like a broken link inside the tree.

A worked example, a project with a site for its users and one for its team:

```lua
-- docs/site.lua
return {
  title = "Shop",
  locales = { { code = "en", label = "English" } },
}
```

```lua
-- Build both sites, strictly: a missing tree or a broken link fails.
doc.generate_project_documentation({
  application = application,
  audiences = { "user", "maintainer" },
  fail_on_problems = true,
})
```

With the files `docs/user/en/index.md`, `docs/maintainer/en/index.md` and the configuration reference generated into
`docs/maintainer/en/configuration.md`, the build writes `docs/dist/user/en/index.html`,
`docs/dist/maintainer/en/index.html` and `docs/dist/maintainer/en/configuration/index.html`, and reports no problem. Without
`audiences`, only `docs/dist/maintainer/` is written. The Hecate website is one tree built by the plain builder; it moves
into `website/user/` and `website/maintainer/` later.

An option or a key of `site.lua` that is not on its list is refused: an old name (`colors`, `theme`, `logo`) with the
name that replaced it, a typo (`audience`) with the closest key.

## Generated pages

`doc.generate_project_documentation(options)` writes the guides of the project and the generated pages below the
locale directory of the guides directory, then runs the site build. It is not the plain builder `doc.build`, which
only turns a content tree into a site. Every option has a default taken from the conventional layout of a project,
so `doc.generate_project_documentation({ application = application })` works from the project directory. A name that
ends in `_dir` is a directory and a name that ends in `_path` is a file; relative paths are relative to `project_dir`.

| Option | Default | Effect |
|---|---|---|
| `project_dir` | `.` | The directory of the project. |
| `guides_dir` | `docs` | The root of the guides: one content tree per audience, `<guides_dir>/<audience>/<locale>/*.md` and `<guides_dir>/<audience>/public/`, and `site.lua`. Generated pages are written into the trees. |
| `audiences` | `{ "maintainer" }` | The trees to build, each into its own site (see "Audiences"). |
| `output_dir` | `docs/dist` | Where the sites are written, one per tree, in `<output_dir>/<audience>/`. It may be below `guides_dir` (the default), but not `guides_dir` or `project_dir`, nor hold either, nor overlap `sources_dir`. |
| `site_configuration_path` | `<guides_dir>/site.lua` | The file that returns the site configuration; a path you give is relative to `project_dir`, the default is below `guides_dir`. `site_configuration` passes the table instead; giving both is an error. A missing file is a `BuildError` that names the remedies. |
| `application` | none | Adds `configuration.md`, one row per key, from the JSON Schema of the configuration the application was given (a page of the `maintainer` tree, written when it is built). The application is the only source: a project without one has no configuration reference. The schema is the single source of the secrets: a key marked `writeOnly: true` or `format: "password"` (`Configuration:schema()` does it for the secrets of `hecate.config`), or that holds such a key below it, never prints its default, its enumeration or its constant. |
| `package_name` | none | Asks for the code reference `reference/<package_name>/`, from the annotated sources in `sources_dir` (default `src`; needs LuaLS). LuaLS runs the plugins that the configurations it reaches declare: the project must be one you trust (see the warning below). |
| `licences_page` | off | Adds the third-party licences page: `true`, or a table `{ rocks_tree_dir, root_rocks, audience, include_bundled }`. |

The other options are `content_locale`, `file_system`, `clean_output_dir`, `fail_on_problems`, `last_updated`,
`language_server_path`, `language_server_config_path`, `theme_file_system` and `theme_files_dir`; they are described in
the README of the package.

Generated pages carry a notice (the first line after the front matter) and `generated: true` in their front matter, and are replaced at each build. A guide cannot overwrite one, and a generated page never overwrites a file that is not generated (a `BuildError` before anything is written); a guide that merely quotes the notice is not generated and is never touched. A generated page is never written through a symbolic link. Generated pages that a build no longer produces are removed. A wrong option, or one that is not on the list (an old name, a typo), raises an `ArgumentError` naming it (`context.argument`). With `fail_on_problems`, one `BuildError` lists every problem of the build, the licences page and the code reference.

A symbolic link in a tree of `guides_dir` or in its `public/` is never followed: it is skipped with a problem, so that a link to a key file or to a parent directory cannot publish or loop. A tree deeper than 32 levels or larger than 100,000 entries is cut with a problem. A heading whose id is one the theme uses (`content`, `sidebar`, `search`, ...) is a problem: write `## Content {#project-content}`. The text that
comes from the schema is escaped, because it is data of the project and not Markdown.

The generator produces no HTTP API reference. The OpenAPI contract is the external documentation of the HTTP API: the application serves it (`/openapi.json`) and `hecate contract export` writes it. A viewer for it, such as Swagger UI, is your own wiring, for example a Docker compose file next to the application. The code reference above is another thing: it documents the Lua modules, classes and functions of `package_name`, from their LuaLS annotations, and no route.

> [!WARNING] Document only sources you trust
> The code reference runs LuaLS, and LuaLS runs arbitrary code. A plugin declared by any LuaLS configuration that it
> reaches is executed with full file and command access, as the user who runs the build. The configurations are the
> `.luarc.json` and `.luarc.jsonc` files and the `Lua.runtime.plugin` setting of `.vscode/settings.json` of the
> documented directory and of the project, and a `.luarc.json` inside the sources directory counts even when
> `language_server_config_path` points elsewhere. Without `language_server_config_path`, no `--configpath` is passed and
> LuaLS finds its configuration by itself. `lua-language-server` is found through `PATH` unless
> `language_server_path` names it, so `PATH` must be trusted too. The library does not warn; the command `hecate doc
> build` is to warn and let you stop (roadmap, `cli` item). Do not request a code reference for a project you do not
> control.

## LuaLS meta files

`doc.project.meta(schemas, namespace)` returns the text of a `---@meta` file: an object schema becomes a
`---@class` with one `---@field` per property, and an enumeration becomes an `---@alias`. The output is
deterministic.

## Theme extension points

The site configuration has options to give a project its own identity. The first three name files of the `public/`
directory of the content root, which the build copies to the root of the site.

| Option | Effect |
|---|---|
| `logo_path` | A path, or `{ light, dark }`. Replaces the hecate logo in the header. The image is shown as it is. |
| `favicon_path` | A path, or `{ light, dark }`, of an `.svg`, `.png` or `.ico` file. Replaces the hecate favicon; the `type` attribute of the `<link rel="icon">` follows the extension. With a pair, each file carries a `prefers-color-scheme` media query. |
| `stylesheet_path` | A CSS file (`.css`) loaded after the theme stylesheet. It overrides the custom properties of the theme: colours in light and dark, code highlighting, the three font families, radii, spacing and the width of the sidebar. It may declare its own `@font-face` for font files of `public/`. |

The option `sidebar_marker` (a boolean, default `false`) draws an accent bar at the left of the current page in the
sidebar. Without it, the current page is shown by a stronger weight and a subtle tint.

A path must be relative, without `..`, a scheme or a query. A file missing from `public/` fails the build
with a `BuildError`. The hecate marks are never recoloured. Template overrides are not offered. Every property,
what it affects and how to ship your own fonts are in [Theme tokens](theme-tokens.md).

Example of `public/theme.css`, with a dark variant (the dark set is written twice: for the system preference and for
the toggle):

```css
:root { --moon: #7a1f3d; --sans: system-ui, sans-serif; }
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) { --moon: #f2b8c9; }
}
:root[data-theme="dark"] { --moon: #f2b8c9; }
```

## llms.txt

Set `generate_llms_txt = true` in the site configuration to have the build write `llms.txt` and `llms-full.txt` at the root of
the site, following the convention of [llmstxt.org](https://llmstxt.org). It is off by default: a project site
publishes nothing for language models until you ask. Without the key, a file `public/llms.txt` of your own is copied
as it is; with the key, a file of `public/` with one of these two names fails the build, because the generated file
would replace it.

- `llms.txt` has the site title, the description of the site, then a link to each published page with the `description` of
  its front matter, grouped by top-level section in the order of the navigation. The links are absolute when `site_origin` is set.
- `llms-full.txt` holds the Markdown of the same pages one after the other, each after a `Source:` line with its URL, in
  the same order. Links between pages are kept as written in the sources.

Only the pages of the tree of the site appear (the other audience has its own files). Only the default
locale is written. The output is deterministic.
