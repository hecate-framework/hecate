# Spike OQ-39: dependencies of `hecate.doc`

Status: **partial** (Markdown, syntax highlighting, search, OpenAPI and WebAssembly measured
on Linux x86_64; macOS and Windows read from build requirements only; no dependency added to
any package or rockspec). Recommendation submitted to the owner; the decision is theirs.
Nothing in this report promotes or changes an ADR. Proposal: [ADR 0022](../adr/0022-doc-dependencies.md)
(Proposed).

## Question

The owner answered the OQ-11 questions on 2026-10-13 ([ADR 0012](../adr/0012-website-generator.md),
"Owner decisions"): avoid coding from scratch where a Lua, C or Rust dependency saves time;
complete GitHub Flavoured Markdown; syntax highlighting for many languages through a
dependency; OpenAPI reference rendering with no new JavaScript development tool; WebAssembly as
much as possible while the site stays deployable as static GitHub Pages files. Which
dependency, per area, and what does each choice imply for the build on three platforms?

- (A) GFM Markdown. (B) Syntax highlighting. (C) Search. (D) OpenAPI reference.
  (E) WebAssembly for runnable examples and a live preview.

## Method

Environment: Linux x86_64 cloud session (4 cores, 16 GB), Lua 5.5.1 (the tarball of the OQ-11
spike), Rust 1.97.0, GCC and CMake, Node 22.22.0, headless Chromium 1194 through Playwright
(preinstalled), emsdk 3.1.74. All third-party code and build output live under `spikes/OQ-39/`
(git-ignored); the sources of the throwaway bindings are in `spikes/OQ-39/{rust-doc,c-cmark,
ts-doc,wasm-doc,wasm-lua,oas-test,size-*}`. Network: `github.com` (git clone and release assets),
`index.crates.io` and the crate downloads, `static.rust-lang.org`, `luarocks.org`,
`storage.googleapis.com` (emsdk) were reachable. **Blocked:** `crates.io/api` (HTTP 403, so no
download counts or reverse dependencies) and `api.github.com` for repositories outside the
session allowlist (release asset lists were probed with `HEAD` requests instead).

Versions: comrak 0.56.0 (BSD-2-Clause), cmark-gfm `27d942c` of 2026-09-28 (BSD-2-Clause, with the
MIT-licensed parts of cmark), pulldown-cmark 0.13.4 (MIT), md4c `60e8065` of 2026-10-13 (MIT),
`cmark` rock 0.31.1 (jgm/cmark-lua, BSD-2-Clause), lunamark `708c670` of 2024-07-01 (MIT, needs LPeg),
syntect 5.3.0 (MIT) with two-face 0.5.2 (MIT OR Apache-2.0), tree-sitter-highlight 0.27.1 with
the grammar crates of the OQ-39 `ts-doc` crate (MIT), Pagefind 1.5.2 (MIT), oas3 0.22.0 (MIT),
roas 0.21.0 (MIT OR Apache-2.0), mlua 0.12.2 (MIT, [ADR 0021](../adr/0021-rust-native-modules.md)).
`lcmark` was cloned but not run: it needs the `cmark` rock, which was evaluated directly.

**Shared sample set:** `website/en/index.md`, `website/en/reference/glossary.md`,
`packages/doc/tests/fixtures/markdown/features.md` (every construct of the first slice), plus a
probe file for GFM extras (`spikes/OQ-39/samples/probe.md`: footnote, alerts, tagfilter, task
list, bare autolinks, table alignment, containers, raw HTML, a `javascript:` link). Where a
larger corpus was needed (benchmark, search) it is the 82 Markdown files of `docs/`,
`website/en` and the package READMEs (300 KB), or the 47 pages that `hecate.doc` builds from
`docs/` (1.6 MB of HTML).

## Findings

### (A) GFM Markdown

**Conformance** (examples passing, HTML normalised with cmark-gfm's own `normalize.py`; each
example runs with the extensions named in its info string; "own" is the first-slice Lua renderer
of `packages/doc`; raw HTML on for the specification runs, as the specifications require):

| Suite | cmark-gfm | comrak | md4c | `cmark` rock | pulldown-cmark | lunamark | own (Lua) |
|---|---|---|---|---|---|---|---|
| CommonMark 0.31.2 (655 examples) | 644 | **655** | **655** | **655** | 634 | 115 | 392 |
| GFM spec 0.29-gfm (670 examples, tables, task lists, strikethrough, autolinks, tagfilter) | **670** | 660 | 654 | 641 | 626 | 116 | 383 |
| cmark-gfm `extensions.txt` (30 examples incl. footnotes) | 29 | 27 | 16 | 2 | 19 | 1 | 2 |

Reading the failures:

- cmark-gfm fails 11 CommonMark 0.31.2 examples (emphasis and one entity example) because it
  implements the 0.29 rules; it passes all of its own 0.29-based GFM suite. comrak is the
  mirror image: its 9 failures on the 0.29 GFM suite are the same emphasis rules, plus
  **tagfilter**, which comrak 0.56 does not implement (no option in the source). In safe mode
  (the default) it omits raw HTML altogether, which is stronger than the tagfilter.
- comrak's two other `extensions.txt` failures are an autolink whose host starts with an emoji
  and a crash-test marked `<IGNORE>`; both are inconsequential.
- md4c: no footnotes, no tagfilter, three task-list and two autolink differences (its
  `md2html` flags were set to the closest GFM equivalents; the result is a floor, not a
  verdict). The `cmark` rock is CommonMark only: no tables, strikethrough, task lists or
  autolinks. lunamark is a Pandoc-style parser, not CommonMark: 115 of 655. pulldown-cmark
  passes raw HTML through by default (a `<script>` in the probe survived), has no bare-URL
  autolink and no tagfilter.
- The first-slice renderer passes 392 of 655, consistent with OQ-37 (a deliberate subset);
  part of the gap is design (raw HTML shown as text, different wrapper markup).

**GFM features on the probe file** (comrak in its default safe mode with the extensions on;
cmark-gfm with its five extensions plus footnotes):

| Feature | comrak | cmark-gfm | pulldown-cmark | md4c |
|---|---|---|---|---|
| tables with alignment | yes (`align=`) | yes | yes (`style=`) | yes |
| task lists | yes | yes | yes | yes |
| strikethrough | yes | yes | yes | yes |
| bare URL, `www.` autolinks | yes | yes | no | yes (flag) |
| footnotes | yes, with back-references | yes, with back-references | yes (different markup) | no |
| alerts `> [!NOTE]` (GitHub syntax, also with a custom title) | **yes** | no (blockquote) | class on the blockquote | no |
| container `::: note Title` | `block_directive` puts the whole info string in `class`: `class="note Custom title"`, so the title is lost | no | no | no |
| raw HTML | omitted in safe mode, comment left | omitted in safe mode | **passed through** | passed through |
| `javascript:` link | `href=""` | `href=""` | kept | kept |
| heading ids | yes (GitHub slugs, an anchor link in the heading) | no | no | no |

**AST access** (for our containers, anchors, outline, link check): comrak exposes the whole tree
(`parse_document`, `NodeValue::Heading`, `Alert`, `Link`, ...), plus adapters for heading
rendering (`HeadingAdapter`), code blocks (`SyntaxHighlighterAdapter`, `CodefenceRendererAdapter`)
and URL rewriting; a 10-line walk produced the heading outline (level and text) in the spike
binding. cmark-gfm exposes an iterator over nodes (C API, same outline in about 25 lines) but
has no adapters and no heading ids, so anchors and highlighting are post-processing. Either way
the Lua side receives what a thin binding of ours returns (HTML, or tables: headings, links,
sections for the search index); the binding is code we own, about 100 lines for the spike.

**Speed** (82 files, 300 KB, in-process from Lua 5.5.1, median of 11 runs; includes the
bindings' overhead):

| Renderer | Time | Throughput |
|---|---|---|
| pulldown-cmark | 2.5 ms | 117 MB/s |
| comrak (all GFM extensions, heading ids, alerts) | 8.1 ms | 36 MB/s |
| cmark-gfm (own binding) | 9.5 ms | 31 MB/s |
| own Lua renderer (first slice) | 155 ms | 1.9 MB/s |

Speed does not decide: even the Lua renderer builds the whole of `docs/` in about 0.2 s.

**Build, packaging, size, licence:**

| | comrak | cmark-gfm | `cmark` rock |
|---|---|---|---|
| Language, build | Rust, `mlua` module (ADR 0021; the OQ-5 fixes for macOS and Windows apply) | C99, CMake or plain `cc`; plus a Lua binding of ours (C API, `luaopen_` with `__declspec(dllexport)` on Windows) | C, LuaRocks build; built unchanged against Lua 5.5.1 |
| Extra crates / sources | 35 crates in the module's tree, 21 of them `mlua`'s; no C of our own | 34 C files | 1 rock |
| Native module size, Linux, stripped | 1.14 MB | 0.35 MB (own binding with the static library) | not measured |
| Licence | BSD-2-Clause | BSD-2-Clause (plus MIT parts, as cmark) | BSD-2-Clause |
| Maintenance seen | v0.56.0, current CommonMark 0.31.2 | last commit 2026-09-28, still on the 0.29 rules | 0.31.1 |
| macOS / Windows | pure Rust; needs the toolchain of ADR 0021 and the link fixes of OQ-5 | needs a C compiler (MSVC works with CMake; not built there) | needs a C compiler |
| wasm32 | `wasm32-unknown-unknown` builds with no change: **383 KB, 127 KB gzipped** (no `wasm-bindgen`, `opt-level=z`) | builds with Emscripten 3.1.74: **241 KB, 78 KB gzipped** | not tried |

The wasm builds were exercised: comrak rendered `features.md` in 9 ms the first time and 0.35 ms
on average over 100 calls in Node; in headless Chromium, loaded from a static HTTP server that
answers `application/wasm`, comrak produced the expected HTML from a page of plain static files.

### (B) Syntax highlighting

Languages asked: Lua 5.5, JSON, shell, HTTP, SQL, TOML, YAML, C, Rust, JavaScript, TypeScript
(plus diff and Dockerfile, which the website will need).

| | syntect, default syntaxes (75) | syntect + two-face (213 syntaxes) | tree-sitter-highlight + grammar crates |
|---|---|---|---|
| Lua | yes | yes | yes |
| JSON, shell, SQL, YAML, C, Rust, JavaScript, diff | yes | yes | yes (SQL through `tree-sitter-sequel`) |
| HTTP | **no** | yes | **no**: the `tree-sitter-http` crate pins `tree-sitter` 0.26 while the highlighter needs 0.27, and Cargo refuses two `links = "tree-sitter"` |
| TOML, TypeScript, Dockerfile | **no** | yes | TOML and TypeScript yes (Dockerfile not tried) |
| Not found by token | | `powershell`, `ps1`, `jsonc` | |
| Output | classes, scope based (`hl-keyword hl-control hl-goto hl-lua`), prefix configurable; we write the CSS | same | classes from the capture names we declare (`ts-keyword`, `ts-string`...), about 25 names, much shorter markup |
| `global <const> x` of Lua 5.5 | `global` shown as a plain variable; `<`, `>` as comparison operators | same | `global` is a keyword and `const` an attribute (the grammar accepts the 5.5 syntax) |
| Module size, Linux | | 1.38 MB (50 crates with `mlua`) | **9.8 MB** (46 crates; each grammar is C code compiled by `cc`) |
| wasm32 | 1.47 MB, 0.72 MB gzipped | 2.06 MB, **1.24 MB gzipped** (the embedded syntax dump dominates) | not tried |
| Licence | MIT; syntaxes carry their own licences (Sublime Packages) | MIT OR Apache-2.0; **the embedded syntaxes keep individual licences** (bat's set), to audit for `THIRD_PARTY_NOTICES` and `cargo-deny` | MIT, every grammar crate MIT (checked in `Cargo.toml`) |
| Regex engine | pure Rust (`fancy-regex`, no C) | same | none (parser tables) |

Notes: tree-sitter highlight queries differ in quality per grammar (spurious `function` on `end`
in Lua, a TOML key span that swallowed its value in the spike output); syntect's Sublime
syntaxes are broader and already themed by scope. syntect can load `.sublime-syntax` files
at build time, so a Lua 5.5 definition of our own (`global`, attributes) is possible; **not tried**.
First call of syntect loads its dump: 53 to 79 ms in Node-wasm, then 0.4 ms per block.

### (C) Search

Corpus: the 47 pages built from `docs/` (3 845 distinct words in Pagefind's count).

| | own pure-Lua index (first slice) | Pagefind 1.5.2 (prebuilt binary, run on the built site) |
|---|---|---|
| Index produced | one JSON per locale, 223 KB raw, 74 KB gzipped, loaded in full on first search | 115 KB of chunks plus 117 KB of page fragments, loaded on demand; entry `pagefind.js` 45 KB, its wasm 72 KB, worker 41 KB (its UI scripts, 120 KB, are not needed: the JavaScript API serves our own dialog) |
| Granularity | section (heading 2 and 3) | page, with excerpts and sub-results |
| Matching | every query word is a prefix in title, heading or text; no stemming, no typo tolerance | stemming per language, tolerant of some misspellings |
| Build time | included in the site build | 0.2 s for 49 pages |
| Deterministic | yes | **yes**: two runs on the same input produced identical directories |
| Offline, static hosting | yes | yes (files only; `.wasm` and `.pf_*` served by GitHub Pages) |
| Languages | folding of case and diacritics | per `<html lang>`, stemming for French among others |
| Tool | none | one MIT-licensed Rust binary: 5.4 MB download (10 MB unpacked); release assets for Linux x86_64 and aarch64 (musl), macOS x86_64 and arm64, Windows x86_64 answered `HEAD` with 200 (**only the Linux x86_64 binary was run**); an "extended" build of 52 MB adds CJK segmentation |

Fifteen queries were run in Chromium against both (own dialog, Pagefind JavaScript API,
`spikes/OQ-39/scripts/search.cjs`). Pagefind found something for "decission" and "cancelation"
where the own index finds nothing, and ranks whole pages (for "yyjson": ADR 0020, the OQ-5 spike,
ADR 0021); the own index returns sections ("cancellation": titles such as "Decision" and "Verification", which say nothing without the page path) and handles prefixes well ("validat": "Validation" and "Types and validation" first, where Pagefind returned two loosely related pages). Both were weak on
"deadline timeout". Neither was judged clearly better; Pagefind gives typo and stemming
tolerance and a smaller first load, the own index gives section anchors and no tool. Pagefind
fits the owner's constraint if a prebuilt binary is not a "development tool" in the JavaScript
sense; that reading is the owner's. **Tantivy** was not built: it is a server-side library
(files, memory maps) without a browser query side, so a static GitHub Pages site would need a
query module in wasm of our own; not evaluated further.

### (D) OpenAPI reference

- **Lua:** `luarocks search openapi` for Lua 5.5 lists only `lua-resty-openapi-validator`
  (OpenResty, a request validator); nothing parses or renders to pages. Not tried.
- **C:** none known; none searched beyond the above.
- **Rust:** `oas3` 0.22 (OpenAPI 3.1 types) and `roas` 0.21 (3.0 and 3.1, with validation) parsed
  a hand-written 3.1 document with `webhooks`, `type: ["string","null"]`, `const`,
  `exclusiveMinimum` as a number, `unevaluatedProperties` and `license.identifier`; `roas`
  reported two real lint findings (an undeclared tag, an unused security scheme). `openapiv3`
  2.2.0 is 3.0 only (not run). None renders documentation; the tree of the two crates is
  95 crates with `mlua`. They would help validation in CI, not page generation.
- **Third-party JavaScript viewers** (Scalar, Redoc, Swagger UI) were excluded by the owner's
  condition and not evaluated.
- The document that `hecate.openapi` will produce is already Lua data (the package has no source
  yet, so the real output was not used): a Lua walk over `paths`, `components.schemas`,
  `webhooks` and `$ref` into static pages is the own-rendering fallback the owner allowed.

### (E) WebAssembly

Extends the OQ-11 result (Lua 5.5.1 builds to wasm with Emscripten and runs in Chromium).

**What runs now.** Of the packages with source, `core` (11 of 11 modules), `doc` (21 of 21, so
the first-slice Markdown renderer and highlighters run in the browser) and 14 of 21
`reactor` modules load with no C module; the scheduler, `fs`, `tcp`, `dns`, `signal` and
`process` need `luv` and do not (a stub that drives the virtual clock only was **not** tried).
`net`: 2 of 8. `json`, `schema`, `router` and `query` have no source yet; `schema` will need the
`json` decoder question of the OQ-11 report.

**Measured** (Emscripten 3.1.74, `-O2`, `lua.c` and `luac.c` excluded, a C entry point of about
45 lines with an instruction-count hook and a counting allocator; the sources of `core`, `doc`
and `reactor`, 322 KB, are embedded as a virtual file system):

| | Measure |
|---|---|
| `hecate_lua.wasm` | 609 KB, 201 KB gzipped (329 KB without the embedded sources, OQ-11); glue 75 KB, 20 KB gzipped |
| Instantiate, then first run | 20 ms; 6 ms (Node) |
| `hecate.core` class example | prints `Hello, Hecate` |
| `hecate.doc.markdown` and `highlight` inside the wasm Lua | render a table, task list, strikethrough in 7 ms; the `global` keyword is highlighted |
| Instruction limit (hook every 50 million instructions) | an infinite loop stops with `instruction limit exceeded` after 385 ms |
| Memory limit (16 MiB counting allocator) | a memory bomb stops with `not enough memory` after 100 ms |
| `io` and `os` | absent (not opened by the entry point) |
| 1 million loop iterations | 7.4 ms |
| Loaded in Chromium from a static HTTP server | worked; `.wasm` is served as `application/wasm` (GitHub Pages does the same; **not deployed to GitHub Pages in this spike**) |

**Build in CI and publication.** The wasm file is produced from the pinned Lua tarball and
`packages/*/src` with a pinned emsdk (3.1.74): `git clone` plus `emsdk install` took about 3 minutes (from the log timestamps) and 1.4 GB (1.2 GB of it under `upstream/`, the LLVM and Emscripten toolchain), so the website workflow must cache the
emsdk directory (key: emsdk version) or build the artefact only when Lua, the entry point or
the embedded sources change; the output joins the Pages artefact as three static files.
The Rust wasm targets need only `rustup target add wasm32-unknown-unknown`. Macros of the
entry point in `emscripten.h` are the only Emscripten-specific code.

**Sandbox.** Measured: instruction hook and memory cap in the wasm state, no `io`/`os`,
`package.cpath` empty. Not measured: a Web Worker with `terminate()` on a wall-clock timeout
(the usual answer to a blocked page), output volume caps, Safari and Firefox, mobile memory.

**Size budget (proposal).** Lua runtime page component: 250 KB gzipped, loaded lazily only on
pages with a runnable example (measured 221 KB with glue). Live editor preview with comrak:
130 KB gzipped (measured 127 KB); with syntect and the 213 two-face syntaxes it would be 1.4 MB
gzipped, which is not worth a preview (a trimmed syntax set was not tried; the 75 default
syntaxes are 0.72 MB). Because the first-slice Lua renderer already runs in the Lua wasm, a
preview needs no second artefact as long as the Lua renderer exists; if comrak replaces it,
comrak.wasm is the preview engine.

## Recommendation

The decision is the owner's. On this evidence, per area:

1. **(A) comrak through `mlua`.** It is the only candidate with CommonMark 0.31.2 at 655/655,
   all GFM extensions we need (including alerts, which GitHub renders too), a full AST with
   adapters for headings and code blocks, no C code, and a wasm build of 127 KB gzipped for
   a live preview. It adds no new category of dependency: Rust through `mlua` is
   [ADR 0021](../adr/0021-rust-native-modules.md). Second choice: cmark-gfm (C, lighter and
   smaller in wasm, 670/670 on its own suite) if Rust is unwelcome here; it needs a binding of
   ours, has no heading ids, alerts or adapters, and lags the 0.31 rules. Not recommended:
   md4c (no footnotes or alerts), the `cmark` rock (no GFM), pulldown-cmark (raw HTML passed
   through, no autolinks), lunamark (not CommonMark).
   *Container syntax:* use GFM alerts (`> [!NOTE]`, with an optional title) rather than
   `::: note`; they render on GitHub, are native in comrak, and map to our four callouts
   (`NOTE`, `TIP`, `WARNING`, `CAUTION` as danger; `IMPORTANT` is extra). Keeping `::: name
   Title` needs a 20-line pre-pass because comrak's `block_directive` loses the title. The
   only container in the existing pages is one note on the home page, so the change is cheap now.
2. **(B) syntect with two-face syntaxes**, classes with the `hl-` prefix, themed with brand
   tokens. All requested languages are covered, it is pure Rust and sits behind the same
   `mlua` module as comrak (1.4 MB), and the same crate is the comrak adapter. Add a Lua 5.5
   syntax of our own (`global`, attribs) as a `.sublime-syntax` file at build time (not
   tried). Alternative: tree-sitter, which already treats `global` as a keyword but costs
   9.8 MB, needs a C compiler on three platforms for every grammar and has no usable HTTP
   grammar crate. An audit of the syntaxes' licences is a prerequisite.
3. **(C) Pagefind as a prebuilt build-time binary, used through its JavaScript API with our
   own dialog**, if the owner accepts a prebuilt Rust binary as "not a JavaScript development
   tool"; otherwise keep the own index (tested only through Chromium by hand; it needs
   an automated test in any case, OQ-36). Pagefind must be fetched per platform
   (checksums pinned in the bootstrap) and its output is deterministic.
4. **(D) Own rendering of the OpenAPI document in Lua**, no dependency. `roas` could later
   validate documents in CI (`hecate contract`), not in `hecate.doc`.
5. **(E) Yes to WebAssembly**, in two steps: the Lua 5.5 runtime for runnable examples of
   `core` now (and `schema`, `router`, `query` when they exist), built in the website
   workflow with a pinned and cached emsdk and published as static files; comrak.wasm for a
   live preview only when the editor preview is wanted.

### What each choice implies for the build on three platforms

| Choice | Linux | macOS | Windows |
|---|---|---|---|
| comrak and syntect (`mlua` module) | Rust toolchain from the bootstrap; prebuilt `.so` in release CI | `-C link-arg=-undefined -C link-arg=dynamic_lookup` (OQ-5) | `LUA_LIB_NAME=lua55`, `LUA_LIB`, `LUA_INC` (OQ-5); no C compiler needed for these crates; **not built here** |
| cmark-gfm alternative | C compiler, CMake | same | MSVC; `__declspec(dllexport)` on `luaopen_*` |
| tree-sitter alternative | Rust plus C compiler | same | same (MSVC) |
| Pagefind | download one binary | download (x86_64 and arm64) | download (x86_64) |
| Lua wasm | emsdk, Linux job of the website workflow only | not needed | not needed |

The documentation build would become a native-module build, so the current rule "Native code:
none" of `packages/doc/CLAUDE.md`, the `modules = {}` rockspec and `check-boundaries` need
changes the owner must approve; end users of `hecate doc build` get the prebuilt module (ADR 0021),
and the first-slice Lua renderer could remain as a degraded fallback where the module is
missing, at the price of two Markdown behaviours. Whether to keep it is a question for the owner.

## Remaining risks

- Rust and `mlua` become a runtime requirement of the documentation build, not only of `net`
  and `json`; a user without the prebuilt module needs a Rust toolchain.
- comrak 0.x API churn (an option, `tagfilter`, disappeared between versions; the major
  version moves often); pin and test the HTML golden files.
- Licences of the two-face syntaxes; `cargo-deny` does not see them.
- Pagefind ships its own JavaScript runtime and a binary index format; both may change between minor versions (1.5.0 had beta releases), so the version is pinned and the search is tested.
- The own highlighter tokens (`tk-*`) of the first slice and the theme CSS change to scope classes.
- Wasm artefacts add build time, a cache and a sandbox to maintain; provenance (pinned
  emsdk, pinned Lua tarball checksum) must be recorded.

## What was NOT done

- **macOS and Windows:** nothing built or run; the table above is read from the OQ-5 findings and the tools' build files.
- **Real OpenAPI output:** `hecate.openapi` has no source; one hand-written 3.1 document (1.9 KB) was used, and no renderer prototype was written (Lua rendering is estimated, not measured).
- **Alternatives not run:** `lcmark`, Discount, hoedown, Tantivy, `openapiv3`, Scalar, Redoc, Swagger UI, `arborium` (a bundle of tree-sitter grammars), Shiki and highlight.js (JavaScript).
- **Syntax set trimming** for the wasm preview, and a Lua 5.5 `.sublime-syntax` of our own.
- **An integration prototype** of comrak into `hecate.doc` (containers, anchors, outline, link check, `sections` for search, highlighting adapter): only the pieces (AST walk, alerts, classed highlighting) were exercised separately; the integration cost is an estimate (about 5 to 8 engineer-days, not measured).
- **Browser Worker timeout, Safari, Firefox, GitHub Pages deployment** of the wasm files.
- **Memory use** of the renderers and **performance at hundreds of pages**; the corpus has 47 pages.
- **`crates.io` statistics** (maintenance, downloads): the API answered 403.
- **Colour contrast** of the syntax classes (the stylesheet is not written).
- Code is in `spikes/OQ-39/` (git-ignored); only this report is versioned.
