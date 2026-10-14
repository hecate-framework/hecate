# Spike OQ-11: documentation tooling

Status: **partial** (two off-the-shelf generators built and rendered, one Lua prototype
built and rendered, Lua 5.5 built to WebAssembly and run in a browser; LDoc and the
Next.js + MDX stack not built; versioning, OpenAPI reference and macOS/Windows builds not
tested). Recommendation submitted to the owner; the decision, and the visual identity, are
theirs. Nothing in this report promotes or changes an ADR.

## Question

1. Which generator route for the documentation site ([ADR 0012](../adr/0012-website-generator.md)):
   (1) adapt an existing generator (VitePress, Astro Starlight, LDoc templates for
   reference only, a Next.js + MDX stack), or (2) `hecate.doc` as a complete generator
   written in Lua 5.5 (owner preference)?
2. Can Lua 5.5 be built to WebAssembly so that examples of pure-Lua packages (`core`,
   `schema`, `router`, `query`) run in the page?

The licence finding on Lua Web Docs (Tailwind UI) and the decision "an original Hecate
theme everywhere" are not reopened; no code or asset of Lua Web Docs was used.

## Method

Environment: Linux x86_64 cloud session, Node 22.22.0, Lua 5.5.1 (tarball checked against
the SHA-256 pinned in `tools/bootstrap/bootstrap.sh`), headless Chromium build 1194 driven
by Playwright 1.56.1 (preinstalled; `playwright install` not run). All third-party code
was installed or built under `spikes/OQ-11/` (git-ignored). Every domain needed was
reachable through the network allowlist: `registry.npmjs.org`, `github.com` (`git clone`;
a `curl` of a GitHub tag archive of emsdk answered 403, `git clone` worked),
`storage.googleapis.com` (emsdk binaries), `www.lua.org`, GitHub release assets
(LuaLS). `wasi-sdk` release assets answered a range request (HTTP 206) but were not used.

**One shared sample set** (`spikes/OQ-11/sample/`, Markdown with front matter `title`,
`description`, `hecate`, `lua`, identical for every candidate):

| Page | Content |
|---|---|
| `en/guide/concurrency.md` | guide page: headings, list, block quote, table, link to the reference page |
| `en/reference/sleep.md` | reference page for `reactor.sleep`, the nine sections of [documentation.md](../architecture/documentation.md), written from the real LuaLS annotations in `packages/reactor/src/hecate/reactor/primitives.lua` (`---@async`, `---@param seconds number`, errors from `packages/core/src/hecate/core/error.lua`) |
| `en/guide/first-example.md` | code sample: a `hecate.core` class (`core.class`, `init`, `core.finalise`); the sample was run on Lua 5.5.1 and prints `Hello, Hecate` |
| `fr/guide/concurrency.md` | French page with `source_revision`; the French reference and example pages are deliberately missing, to see the fallback behaviour |

Each candidate was given the same minimal brand override (a purple accent, light and
dark), so the comparison is about structure and defaults, not about colour. **The purple
is a placeholder of mine, not a proposal for the visual identity.**

Candidates:

- VitePress 1.6.4 (MIT; `next` tag is 2.0.0-alpha.20), default theme, local search provider.
- Astro 7.3.8 with Starlight 0.42.6 (MIT; Starlight's peer range requires Astro ^7.2.10),
  default theme, built-in Pagefind 1.5.2 search.
- `hecate-doc` prototype (own, `spikes/OQ-11/hecate-doc/`, about 340 lines of Lua 5.5, no
  dependency, uses the 5.5 `global` declaration): Markdown subset renderer
  (front matter, headings with anchors, paragraphs, lists, fenced code with a small Lua
  highlighter, pipe tables, block quotes, code spans, emphasis, links), HTML template
  with sidebar, table of contents, locale switcher, English fallback with a visible
  notice, skip link, light/dark theme (system preference plus a toggle), a JSON search
  index per locale and 30 lines of client-side search.

Screenshots (1280x900, light and dark through the browser colour scheme, plus 390 px
wide) are in [OQ-11-samples/](OQ-11-samples/), named `<candidate>-<page>-<scheme>.png`
(`guide`, `ref`, `code`, `fr`; `ref-mobile`), plus `wasm-example.png`. Scripts:
`spikes/OQ-11/pw/`.

## Findings

### Rendered candidates

| | VitePress 1.6.4 | Starlight 0.42.6 | `hecate-doc` prototype |
|---|---|---|---|
| Build, 3 runs, wall clock (3 English pages + French) | 4.3 to 4.8 s | 3.3 to 3.7 s | 0.046 to 0.055 s |
| Output (`du`, files) | 1.2 MB, 42 files | 1.3 MB, 44 files (includes Pagefind) | 96 KB, 13 files (34.5 KB of content) |
| Gzipped JS + CSS + HTML | 115 KB | 191 KB | 5.8 KB (all files) |
| Tool footprint | `node_modules` 103 MB, 126 packages | `node_modules` 230 MB, 276 packages (install 21 s) | 0 (Lua 5.5 only) |
| Runtime required to build | Node >= 18 | Node >= 22.12 | Lua 5.5 (already in the CI bootstrap) |
| Dependency licences (scan of `package.json` of the whole tree) | 120 MIT, 2 ISC, 3 BSD, 1 CC0 (icons data) | 240 MIT, 9 ISC, 5 Apache-2.0, 8 BSD-2, 3 BSD-3, 3 BlueOak, 2 MPL-2.0 (lightningcss), 2 CC0, 1 0BSD, 1 Python-2.0 (argparse), **LGPL-3.0 in `sharp-libvips`** (image library binary pulled by `sharp`) | none |
| `npm audit` | 3 (2 moderate, 1 high): `vite`/`esbuild`, development server | 10 moderate | not applicable |
| i18n en/fr | routing by folder, language menu; **no fallback**: `/fr/reference/sleep` does not exist (404), nothing flags it | routing by folder, language menu; **fallback to English with a built-in notice** (verified in the generated HTML) | folder routing, switcher, fallback with notice (mine, about 15 lines); `source_revision` is read nowhere |
| Search | local MiniSearch index, in the bundle | Pagefind index of the built HTML, per language | JSON index emitted, naive substring ranking in the client |
| Versioned docs | none built in (common practice: one build per version plus a nav dropdown) | none built in; community plugin `starlight-versions` 0.10.1 (MIT), **not tested** | not implemented |
| Reference page template (9 sections) | Markdown only; no structure imposed | Markdown only; no structure imposed | Markdown only here; a template would be written for `hecate.doc` |
| Code highlighting | Shiki, Lua grammar | Shiki (Expressive Code), Lua grammar | own 40-line lexer (keywords, strings, comments, numbers); crude |
| Dark mode | yes (follows system, toggle) | yes (follows system, 3-state selector) | yes (system, toggle) |
| Last release seen on npm | 2026-09-04 | 2026-10-08 | not applicable |

Notes on the table:

- Sizes and times are for a 4-page sample and say nothing about scaling. The two JS
  generators have a fixed cost (bundler start, Vite builds) that will shrink relative to
  content; the prototype's per-page cost was not measured at scale.
- Starlight rendered the front-matter `title` as an `<h1>` and the `# ...` of the body
  again (a duplicated title in `ref-*.png` and `code-*.png`); VitePress takes the body
  `<h1>` only. A content convention (title in front matter only, or in the body only)
  must be chosen, and the Markdown files must follow it whatever the generator.
- The French page of the sample links back to English pages through the fallback only in
  Starlight and in the prototype.

### Accessibility basics (superficial, not an audit)

Computed colour contrast on the first paragraph, first link and first inline code of the
reference page, from the browser's computed styles (one element each, no WCAG tool, no
screen reader, no zoom or reflow test):

| Contrast ratio | VitePress light / dark | Starlight light / dark | prototype light / dark |
|---|---|---|---|
| paragraph text | 10.9 / 12.8 | 11.7 / 10.1 | 16.8 / 15.5 |
| link | 7.1 / 9.3 | 7.1 / 9.6 | 8.8 / 10.1 |
| inline code | 7.1 / 9.3 | 10.1 / 6.6 | 15.1 / 14.1 |

All measured values are above the WCAG 2.2 AA thresholds (4.5:1). The link colour is my
placeholder accent for the three candidates, so these numbers say little about the
products themselves. Keyboard: in all three the first Tab stop is a "Skip to content"
link, followed by the logo and the header controls in a logical order; focus rings were
visible in the prototype (3 px outline) and not inspected on the other two. At 390 px
width none of the three scrolls horizontally (the prototype did at first: its header
overflowed; fixed in the spike). Syntax-highlight token colours were not measured.

### Route 2 prototype and effort

The prototype shows that the visible core of a static generator (Markdown subset,
template, theme, locales, search index) is small in Lua 5.5 and fast (50 ms). It also
showed what pure Lua 5.5 does not provide, which the real package needs from other
Hecate packages: listing a directory and creating directories (the prototype used a
hard-coded page list and `mkdir -p` through `os.execute`), hence `hecate.reactor.fs`
(libuv); `packages/doc/README.md` does not list `reactor` among its dependencies (it
lists `core`, `openapi`, `schema`, `json`).

**LuaLS export (measured, LuaLS 3.19.1 as pinned in CI, `--doc` on `packages/reactor/src`
and `packages/core/src`, 0.6 s):** the JSON export lists `---@class` types and their
fields and methods, with `async`, parameter names and types, return types, and
descriptions. Two gaps matter for the reference template:

- Functions that live on a plain module table rather than a `---@class` are absent: the
  word `sleep` does not occur in the reactor export, and `hecate.core` exports its error
  classes but not `class`, `trait`, `interface` or `finalise`. The sample page
  `reactor.sleep` could therefore not have been generated from the export as the code is
  organised today. Either modules are annotated as classes (`---@class hecate.reactor`
  on the module table), or `hecate.doc` reads the annotations itself (a second parser).
  Not tried: a LuaLS-side workaround.
- Parameter and return descriptions are kept only when written on the same line as the
  annotation (11 of 127 parameters and 3 of 51 returns have one in `reactor`; 13 of 80
  and 0 of 37 in `core`), so the "Parameters and return values" section needs a
  convention in `docs/architecture/coding-standards.md` to be useful.

**Estimated effort, focused engineer-days, my estimates, not measured, not calibrated
against agent throughput.** "Shared" means the work is needed whichever route is chosen
(Markdown files for the website, reference generation).

| Component | Route 2 (`hecate.doc`) | Route 1 (Starlight or VitePress) | Written from scratch / reused |
|---|---|---|---|
| Markdown rendering (CommonMark + tables, task lists, anchors, admonitions, includes of tested example files) | 8 to 12 (the prototype covers a subset in about 170 lines; the CommonMark conformance suite of about 650 examples is the real cost) | 0 | scratch, or a Lua library (see dependencies) |
| Syntax highlighting (Lua, shell, JSON, HTTP, SQL, diff) | 4 to 6 | 0 (Shiki; does not know the 5.5 `global` keyword, to check) | scratch |
| Template engine | 0 if `hecate.template` exists first, else 3 to 4 | 0 | reuse `hecate.template` (planned) |
| Theme: CSS, scripts, responsive, dark, accessibility pass, owner iterations | 8 to 12 | 5 to 8 (override layer on someone else's markup) | scratch either way |
| Site model: front matter, navigation, table of contents, anchors, link check, sitemap, `llms.txt`, 404 | 5 to 7 | 1 to 2 (configuration), `llms.txt` and link check still ours | partly reuse `check-links` logic |
| LuaLS export ingestion into the 9-section Markdown (shared) | 6 to 10 | 6 to 10 | scratch; `hecate.json` for the export |
| OpenAPI reference (interactive) | 10 to 15 for an own renderer; 2 to 3 to embed a third-party viewer | 2 to 3 (viewer) or a plugin, not evaluated | scratch, or third-party JS |
| i18n: locale tree, fallback, string tables, translation status from `source_revision`, keyed translation of generated pages | 4 to 6 | 2 to 3 (fallback built in for Starlight; status check and keyed translations still ours) | scratch |
| Search | 3 to 5 for own client ranking; 1 to 2 with a third-party index | 0 (built in) | scratch, or third-party |
| Versioned docs (one build per minor, switcher, `latest`, redirects) | 4 to 6 | 3 to 5 (build orchestration, plugin or dropdown) | scratch |
| Development server with watch (needs `http` and `reactor`) | 3 to 5 | 0 | scratch |
| Runnable examples in WebAssembly (CI build, worker, sandbox, UI) | 5 to 8 | 5 to 8 (same work, as a component) | scratch plus emscripten |
| Cross-platform CI, tests, benchmarks, package documentation | 5 to 7 | 2 to 3 | scratch |
| **Whole package** (low end: third-party OpenAPI viewer and search, `hecate.template` available; high end: everything in-house) | **about 55 to 100** | **about 26 to 42** | |
| **Minimal useful `hecate.doc`** (Markdown, highlighting, theme, site model, LuaLS ingestion, i18n, own search; no OpenAPI, versioning, dev server or WebAssembly) | **about 38 to 62** | | |

Third-party dependencies route 2 may need (each needs an ADR; none was added):
a Markdown parser if not written in-house (`lunamark` needs LPeg; a `cmark` binding is
C), a client search library or Pagefind (MIT, a Rust binary that indexes any HTML, so it
works with a generator of our own), an OpenAPI viewer in JavaScript (Scalar, Redoc or
Swagger UI, each with its own licence, not checked), a self-hosted font if one is wanted
(the VitePress and Starlight builds bundle Inter, SIL OFL). With everything written
in-house, route 2 has no third-party dependency and the site builds on any platform
where the Lua 5.5 bootstrap runs.

Route 1 makes Node >= 22 (and a 100 to 230 MB `node_modules`) a requirement of the
documentation build, in CI and for the contributors who build the site. It also means
`hecate doc build` for **user projects** (documented in
[documentation.md](../architecture/documentation.md)) would either require Node on the
user's machine or ship a bundled copy of the generator. That is the main structural
difference between the routes, and it is a product decision, not a technical one.

### Lua 5.5 in WebAssembly

- Built from the unmodified Lua 5.5.1 tarball (sources of `lua.c` and `luac.c` excluded)
  with Emscripten 3.1.74 (emsdk, clang), `-O2`, plus a 15-line C entry point
  (`hecate_run`, a fresh state per run). **No patch, no warning, 6 s build.** Output:
  `hecate_lua.wasm` 329 KB (129 KB gzipped) and the JavaScript glue 75 KB (20 KB
  gzipped; it also embeds the `hecate.core` sources as a virtual file system).
- Run in headless Chromium from a local HTTP server, with an editable `<textarea>` and a
  Run button (`wasm-example.png`): the `hecate.core` sample of the guide prints
  `Hello, Hecate`; `_VERSION` is `Lua 5.5`; a runtime error returns its message
  (`attempt to perform arithmetic on a nil value`); the 5.5 `global` declaration works as
  in native Lua (a script that declares `global x` loses implicit access to `print`,
  and runs correctly once `print` is declared). `hecate.core` itself, which uses
  `global <const>`, loaded without change.
- Timings, single page, local server, not repeated: page load plus first run 328 ms;
  running the sample 25 ms. An indicative micro-benchmark (2 million table inserts) took
  144 ms in WebAssembly against 31 ms with the native Lua 5.5.1 interpreter on the same
  VM, about 4.6 times slower; one run each, not a benchmark.
- What can and cannot run today: of the four packages named in the question, **only
  `core` exists** (`schema`, `router` and `query` have no source yet), so only `core` was
  run. `schema` depends on `hecate.json`, whose decoder is the C library yyjson
  ([ADR 0020](../adr/0020-json-yyjson-decoder-serde-encoder.md)); in the browser it
  would need yyjson compiled to WebAssembly too, or the pure-Lua decoder lunajson kept as
  a documented fallback (correct on integers, about 10 times slower than yyjson in OQ-5).
  `hecate.reactor` loads `luv` at require time (`reactor.lua`, `fs.lua`, `signal.lua`,
  `process.lua`), so it does not run in the browser; a `luv` stub driving only the
  virtual clock was **not** tried.
- Not tested: infinite loops and memory limits (a Web Worker with termination and an
  instruction-count hook would be the usual answer), loading many package files, Safari
  and Firefox, `wasi-sdk` as an alternative toolchain, size of an embedded multi-package
  file system, and the CI cost of the emsdk (the install pulled about 1.4 GB into
  `spikes/OQ-11/`; a one-off build whose artefacts are cached or published would avoid
  that on every build).

## What was NOT done

- **LDoc** and the **Next.js + MDX** stack were not installed or rendered. LDoc parses
  LDoc-style comments rather than LuaLS annotations and its Lua 5.5 support was not
  checked; the Lua Web Docs stack is Tailwind UI based and excluded by the licence
  finding. Docusaurus, Hugo, mdBook and others were not considered.
- **Versioned documentation** was tested in no candidate (only the plugin's existence and
  licence were checked).
- **OpenAPI reference** was rendered by no candidate.
- **macOS and Windows**: nothing was built there. Both JavaScript generators and Pagefind
  are published for those platforms, but this was not verified; the prototype uses
  `mkdir -p` and would need `hecate.reactor.fs`.
- **Visual identity**: the roadmap points to the `brand/` directory of the organisation
  `.github` repository; it was not available to this session and was not consulted. The
  colours, type and the `Hec`**`a`**`te` wordmark treatment in the prototype are
  placeholders.
- No accessibility audit (see above), no performance test at scale (hundreds of pages,
  a generated reference of `reactor` and `core`), no incremental build measurement.
- The Starlight and VitePress customisation was limited to CSS tokens; their extension
  APIs (components, plugins) were not exercised, so "can be themed as MDN-like" is not
  demonstrated beyond colours.
- `npm audit` findings were counted, not analysed.
- Code is in `spikes/OQ-11/` (git-ignored); only the report and the screenshots are
  versioned.

## Recommendation

The decision is the owner's. On this evidence:

1. **Route 2 is technically credible**, and it is the only route that gives user projects
   a documentation build without Node (`hecate doc build`). The visible core is cheap
   (the prototype renders the sample in 50 ms with no dependency); the real cost is in
   Markdown conformance, highlighting, the theme, the reference generator and the
   OpenAPI view: about 38 to 62 engineer-days for a minimal useful package and 55 to 100
   for the full specification (estimates).
2. **Timeline mismatch to settle:** the roadmap wants documentation before the first
   usable framework version (Phase 2 item "Website skeleton"), while `doc` is a Phase 3
   package behind `openapi`, `schema` and `json`. Waiting for `hecate.doc` delays the
   public site; pulling a minimal `doc` forward changes the roadmap.
3. **If the public site must come first,** Starlight is the better of the two tested
   off-the-shelf generators for this content: English fallback with a notice, per-language
   search and a ready navigation come for free, build time is 3 to 4 s. VitePress has a
   smaller dependency tree (126 against 276 packages) but no fallback and no
   versioning. Both need Node 22 in the website CI only. Because ADR 0012 already keeps
   the content generator-independent, the pages written meanwhile survive a later move to
   `hecate.doc`; the theme work would be redone.
4. **A staged route keeps both options open:** shared work first (Markdown conventions,
   LuaLS export ingestion producing the nine-section Markdown, translation status), then
   either a Starlight site now and `hecate.doc` for user projects later, or a minimal
   `hecate.doc` that replaces Starlight when it reaches parity. The reference generator
   is needed in every case and is the right first piece.
5. **WebAssembly:** Lua 5.5 builds cleanly and runs in the browser; runnable examples
   are feasible for `core` today and, for the other three packages, once they exist and
   once the `json` question for `schema` is answered. This is independent of the
   generator route: the page component is the same.

### Remaining risks

- The LuaLS `--doc` export omits functions on plain module tables (see above). Without a
  change of annotation style or a second parser, the generated reference is incomplete.
- A custom theme on someone else's generator (Starlight, VitePress) fights their markup;
  VitePress 2.0 is still alpha, and Starlight tracks Astro majors closely (0.42 needs
  Astro 7.2.10 or later), so upgrades are frequent.
- Route 2: the estimate is large, Markdown edge cases are a long tail, and the package
  would compete for time with the framework itself.
- `sharp` brings an LGPL-3.0 shared library into Starlight's tree (binary, build-time
  only); the licence implications for the repository were not analysed.
- Runnable examples add a published WebAssembly artefact (size, provenance, build
  reproducibility) and a sandboxing question for user-edited code.

## Questions for the owner

1. **Route:** (a) `hecate.doc` for everything, accepting the effort and the delay of the
   public site; (b) Starlight (or VitePress) for the public site now, `hecate.doc` later
   for user projects; (c) off-the-shelf generator for the framework site only and no
   `hecate doc build` site generation for user projects. Is a Node-free
   `hecate doc build` a requirement?
2. **Timeline:** may a minimal `hecate.doc` (or the reference generator alone) be pulled
   forward from Phase 3, with the dependency change that implies (`json`, `reactor`
   for the file system)?
3. **Visual identity:** the screenshots use a placeholder purple. Which colours, wordmark
   and typography (system fonts or a self-hosted font such as Inter, OFL) does the owner
   want, and may agents read the `brand/` directory of the `.github` organisation
   repository? Is the layout of the `hecate-doc` prototype (sidebar, central column,
   table of contents on the right, light and dark) the intended MDN-like direction, or
   should another reference page layout be tried?
4. **Third-party dependencies in `hecate.doc`** (each needs an ADR): Markdown parser
   (write in-house, or `lunamark`/`cmark`), search (own, MiniSearch or Pagefind),
   OpenAPI viewer (own, or Scalar, Redoc, Swagger UI), highlighting (own lexers).
5. **WebAssembly:** go or no-go for runnable examples; start with `core` only? Is a
   published `.wasm` artefact acceptable, and who owns its build in CI?
6. **Content conventions:** page title in front matter only, or also as a Markdown `#`
   heading; whether code samples must be included from tested files from the start.
7. **Reference generation:** annotate every module table as a `---@class` (so that the
   LuaLS export contains its functions) or have `hecate.doc` parse annotations itself?
   Which description convention for parameters and returns?
