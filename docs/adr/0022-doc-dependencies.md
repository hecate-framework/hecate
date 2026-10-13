# 0022 — Documentation generator: third-party dependencies and WebAssembly assets

- **Status:** Proposed
- **Date:** 2026-10-13
- **Deciders:** project owner (to promote)
- **Packages:** doc, website, cli (and the bootstrap, CI and release tooling)
- **Related:** [ADR 0012](0012-website-generator.md) (owner decisions of 2026-10-13), [ADR 0021](0021-rust-native-modules.md), [spike OQ-39](../spikes/OQ-39-doc-dependencies.md), [documentation.md](../architecture/documentation.md), OQ-11, OQ-35 to OQ-39

## Context

The owner decided on 2026-10-13 (ADR 0012) that `hecate.doc` generates everything, that
dependencies are preferred to code written from scratch where they save time (complete
GitHub Flavoured Markdown, syntax highlighting for many languages, no new JavaScript
development tool for the OpenAPI reference), and that WebAssembly is used as much as possible
while the site stays deployable as static GitHub Pages files. The first slice of `hecate.doc`
has an in-house Markdown renderer (392 of 655 CommonMark 0.31.2 examples), five highlighters
and a pure-Lua search index. The spike [OQ-39](../spikes/OQ-39-doc-dependencies.md) compared
candidates on one sample, on Linux.

## Options considered

1. **Markdown:** comrak through `mlua`; cmark-gfm (C) with a binding of ours; md4c; the `cmark`
   rock; pulldown-cmark; lunamark; the in-house renderer. Measured: CommonMark 0.31.2 passed 655
   (comrak), 644 (cmark-gfm), 655 (md4c, `cmark` rock), 634 (pulldown-cmark), 115 (lunamark).
   GFM extensions and footnotes: complete in comrak and cmark-gfm only.
2. **Highlighting:** syntect with two-face syntaxes; syntect default syntaxes; tree-sitter
   with grammar crates; the in-house lexers. Measured: 213 syntaxes covering every language
   asked in two-face; the tree-sitter module is 9.8 MB and has no usable HTTP grammar crate.
3. **Search:** the in-house index; Pagefind as a prebuilt binary; Tantivy (not built: no browser
   query side).
4. **OpenAPI:** own rendering of the document; `oas3` or `roas` (parse and validate, 3.1);
   third-party JavaScript viewers (excluded by the owner's condition).
5. **WebAssembly:** none; Lua 5.5 runtime for runnable examples; comrak (and syntect) in wasm
   for a live preview.

## Decision (proposed)

- **Markdown: comrak**, in one Rust native module of `hecate.doc` bound through `mlua`
  (ADR 0021; same build, shipping and `cargo-deny` rules), configured with the GFM extensions
  (tables, task lists, strikethrough, autolinks, footnotes, alerts) in safe mode, with heading
  ids and an AST walk that returns the outline, the links and the sections to Lua. cmark-gfm is
  the named alternative if Rust is rejected for the documentation build.
- **Callouts are GFM alerts** (`> [!NOTE]`, optional title), mapped to the four callouts of the
  theme (`NOTE`, `TIP`, `WARNING`, and `CAUTION` as danger; `IMPORTANT` as an additional
  note-level callout). The `::: name Title` container of the first slice is retired when comrak
  is integrated. This changes the container convention of OQ-35.
- **Highlighting: syntect with the two-face syntax set**, in the same native module, emitting
  CSS classes with the `hl-` prefix; the stylesheet maps scope families to brand tokens in light
  and dark (OQ-34, point 4). A Lua 5.5 syntax definition of our own is added if the shipped
  definition does not treat `global` and attributes correctly (it does not today). The licences
  of the embedded syntaxes are audited and recorded in `THIRD_PARTY_NOTICES` before adoption.
- **Search: Pagefind**, a prebuilt binary run on the built site, queried through its JavaScript
  API from our own search dialog, **provided the owner accepts a prebuilt Rust binary as not
  being a JavaScript development tool**. The binary is pinned by version and checksum per
  platform and managed like other toolchains (ADR 0010). If not accepted, the own index stays and
  gains an automated test.
- **OpenAPI: own rendering** from the OpenAPI JSON produced by `hecate.openapi` into static
  pages, in Lua, with no dependency. `roas` is a candidate for contract validation in CI,
  outside `hecate.doc`.
- **WebAssembly:** the website workflow builds a Lua 5.5 runtime with a pinned Emscripten
  (3.1.74 in the spike) from the checksum-pinned Lua tarball, embeds the pure-Lua packages that
  can run (`core` today), and publishes `.wasm` and glue as static files of the Pages
  artefact; the page component loads it lazily, runs code in a Web Worker with a wall-clock
  timeout, an instruction-count hook and a memory cap, without `io` or `os`. Budget: 250 KB
  gzipped for the runtime component. comrak compiled to `wasm32-unknown-unknown` (about 130 KB
  gzipped) serves a live editor preview only when one is built; syntect is not shipped to the
  browser (1.2 MB gzipped).
- **Fallback.** The in-house Markdown renderer and highlighters stay until the native module
  lands and are then retired, unless the owner wants a pure-Lua degraded mode for platforms
  without the prebuilt module (two Markdown behaviours to maintain).

## Consequences

- `packages/doc` gets native code: `packages/doc/CLAUDE.md` ("Native code: none"), the README
  row, the rockspec (`modules = {}`) and `check-boundaries` change; the layout of the Rust crate
  follows the convention chosen for `net` and `json`. These changes need the owner's approval
  and are not made by this ADR.
- Dependencies added when accepted: `mlua` (already accepted), `comrak`, `syntect`, `two-face`
  and their crates (35 for comrak, 50 for syntect with `mlua`, both without C code), Pagefind
  1.5.x (a binary), emsdk (a CI toolchain). No dependency is added by this step.
- `ci-engineer`: Rust job for the module on three platforms (OQ-5 link fixes), a Pagefind
  download step per platform, an emsdk cache in the website workflow. `release-manager`:
  prebuilt module in release artefacts.
- The first-slice code, tests and golden files (`markdown_golden_test.lua`, highlighters,
  search) are replaced by tests of the integration (HTML golden files pinned to the comrak
  version; the CommonMark and GFM specification examples can then run as a test through the
  module, which settles OQ-37).
- Roadmap: the minimal `hecate.doc` and the reference generator are pulled forward
  ([roadmap](../roadmap.md)); the Lua 5.5 wasm component and Pagefind integration follow it.

## Verification

CI builds the native module on Linux, macOS and Windows and runs the specification examples
through it; `cargo-deny` and `check-licenses` cover the crates and the syntaxes; the website
workflow builds the wasm files and checks their size against the budget; a golden-file test per
highlighted language; a browser test (headless Chromium) of the search dialog and of one
runnable example, including the timeout.
