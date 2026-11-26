# 0032 — Unicode normalisation: the `unicode` package and the `unicode-data` rock versioned by Unicode version

- **Status:** Accepted
- **Date:** 2026-11-17
- **Deciders:** project owner (route chosen in chat on 2026-11-17, on pull request #218; accepted by the owner in chat on 2026-11-17)
- **Amended:** 2026-11-19 by the owner, in place, status unchanged: first pinned version Unicode 18.0.0; error classes listed
- **Amended:** 2026-11-25 by the owner, in place, status unchanged: the module reports the Unicode version as `unicode_version` (as `hecate.unicode_data` does) and `version` is the version of the package, the lockstep `VERSION`, as in every other package (OQ-150)
- **Packages:** unicode (new), unicode-data (new), doc (first user), schema and router (later users), and the generator, CI and release tooling
- **Related:** OQ-140 ([issue #219](https://github.com/hecate-framework/hecate/issues/219)), [ADR 0005](0005-single-brand-monorepo-lockstep-versioning.md) (lockstep versions), [ADR 0017](0017-monorepo-with-read-only-mirrors.md), [ADR 0018](0018-error-signalling.md), [ADR 0021](0021-rust-native-modules.md), [ADR 0022](0022-doc-dependencies.md), [overview.md](../architecture/overview.md)

## Context

`hecate.doc` compares page ids in Unicode Normalization Form C (NFC), so that `cafe` followed by
U+0301 and U+00E9 are one page whatever the file system that authored the tree. Without a Unicode
database in the repository, the first slice uses an in-repository table of the canonical
compositions of Latin letters (`hecate.doc.internal.page_id`). OQ-140 lists its gaps: Vietnamese
letters with two marks outside the table, Romanian letters with comma below, singleton
decompositions (U+212B ANGSTROM SIGN, U+2126 OHM SIGN), Greek with tonos, Cyrillic, Hangul, and the
canonical reordering of several combining marks. Other packages will meet the same need: `schema`
(comparison and `uniqueItems` of strings are code-point based, but a user-facing "canonically
equivalent" check is a plausible request) and `router` (percent-decoded path segments compared with
registered literals).

The owner decided on 2026-11-17 to complete the normalisation properly and asked for the data to
follow the Unicode release cycle independently of the framework cycle. The framework releases in
lockstep (ADR 0005); Unicode publishes a new version about once a year, and each version can add
characters but, by the Unicode Normalization Stability Policy, never changes the normalisation of a
character already assigned: a string normalised under one version is still normalised under every
later version, and the decomposition, combining class and composition of an assigned character
never change.

Third-party data needs an ADR (CLAUDE.md, ADR 0022 as precedent). The Unicode Character Database
(UCD) is published under the Unicode License v3 (SPDX `Unicode-3.0`), a permissive licence that
requires the copyright and permission notice to accompany the data and its derivatives.

The Lua 5.5 standard library has `utf8` (encoding, decoding, iteration) and nothing on
normalisation, case mapping or segmentation.

## Options considered

1. **Keep the Latin table** (OQ-140, option a). No new package, no data licence. The gaps listed in
   OQ-140 remain, and any new user (`schema`, `router`) either copies the table or reaches into
   `doc` internals, which layering forbids. Rejected by the owner.
2. **Vendor `luautf8`** (MIT, C, version 0.3.0, checked on LuaRocks on 2026-11-17). It offers NFC
   only (no NFD), has a C build on three platforms, brings its own tables that we do not control
   (the Unicode version is whatever the rock ships) and is a new third-party dependency. Related
   rocks checked the same day: `luaucdn` (MIT, bindings of the C library `ucdn`, C again),
   `dromozoa-utf8` (GPL-3, pure Lua, incompatible with an MIT framework), `unicode-data` (LPPL, a
   different project: it is not about normalisation); no `utf8proc` rock exists.
3. **A native crate** (`unicode-normalization` through `mlua`, ADR 0021). Correct and fast, but a
   native module for what is a table lookup, a new crate, a per-platform build for a package that
   is otherwise pure Lua, and the Unicode version is bound to the framework's build. Rejected for
   now; the choice is kept open (see Consequences).
4. **One `unicode` package that holds code and data.** Simple, but then the Unicode version moves
   only with the framework: a user who needs the characters of a new Unicode version has to wait
   for a framework release and upgrade the whole framework.
5. **Two packages: `unicode` (algorithms) and `unicode-data` (generated tables)**, the data rock
   versioned by the Unicode version. A user upgrades Unicode with
   `luarocks install hecate-unicode-data` and nothing else.

## Decision

Option 5.

### Packages, layer and names

- **`packages/unicode`**, rock `hecate-unicode`, module `hecate.unicode`: the algorithms, pure Lua.
  Scope of the first version: NFC and NFD of UTF-8 strings, the Hangul syllable arithmetic
  (algorithmic: not in the tables), canonical reordering by combining class, and the Unicode
  version in use (`unicode.unicode_version`). Out of scope: NFKC and NFKD (they need the compatibility
  mappings, a larger table: additive later, in the same data rock), case mapping and case folding,
  grapheme and word segmentation, collation, identifier profiles. Invalid UTF-8 is an error object
  of the Hecate hierarchy (ADR 0018), one of the classes listed under "Error classes" below.
- **`packages/unicode-data`**, rock `hecate-unicode-data`, **module `hecate.unicode_data`**: pure
  Lua, generated tables only, no code other than the loader that returns them, no dependency. The
  directory and rock follow the rule of ADR 0017 and the overview (`packages/<name>`,
  `hecate-<name>`); the module root replaces the hyphen of a multi-word name with an underscore,
  because `hecate.unicode-data` cannot be written as a field access and because a module inside
  `hecate.unicode` would make two rocks share one directory and one namespace (file clashes at
  install, unclear ownership). This is the first multi-word package name: the naming rule of the
  overview is completed accordingly when the ADR is accepted, and `check-package-structure` accepts
  the underscore form.
- **Layer: 0 (Foundation), next to `core`, for both packages.** The architecture rule allows a
  dependency on a lower or the same layer; the lowest layer is the one that every other package may
  use. `unicode` does no I/O and needs no reactor; its only Hecate dependencies are `core` (error
  objects and class model, same layer) and `unicode-data` (a leaf). Placing it in layer 1 or 2
  would forbid `json` or `core` consumers from using it for no benefit, and placing it in the
  tooling group would forbid `schema` and `router` (layer 2) from depending on it, which is the
  stated future need. `doc` (tooling) uses it as a dependency of a lower layer. `core` does not
  depend on `unicode`, so there is no cycle. `gen-dependency-graph` and `check-boundaries` get the
  two entries when the packages are scaffolded.
- **Version and lockstep.** The rock version of `hecate-unicode-data` **is the Unicode version**,
  `18.0.0-1` for Unicode 18.0.0, the first pinned version (the draft of this ADR used 17.0.0 as its
  example; the revision after the dash is for repackaging of the same Unicode version, such as a
  generator fix). This is an **exception to the lockstep versioning of
  ADR 0005**, recorded here: `hecate-unicode-data` is released on the Unicode schedule, not with
  `VERSION`; `check-versions` and `gen-rockspecs` exempt it, and the framework's release process
  does not bump it. `hecate-unicode` is lockstep like every other package.
- **Dependency range.** `hecate-unicode` declares `hecate-unicode-data >= 18.0.0` (the version it
  was tested against and whose conformance fixture it pins), with **no exact pin and no upper
  bound**. The meta-rock `hecate` depends on `hecate-unicode` (through `doc` and, later, `schema`
  and `router`), so the data comes along at its minimum version unless the user installs a newer
  one. The data module exposes `unicode_version` (a string `"18.0.0"`) and `format` (an integer,
  the layout of the tables). `hecate.unicode` checks `format` when it loads the tables and fails
  with a precise error if it does not know it. The layout is meant to be stable for the whole life
  of a Hecate major version; a change of layout requires a new ADR and a release of `hecate-unicode`
  that accepts both layouts before any data rock uses the new one.
- **Upgrading is safe, mixed fleets are harmless.** Because of the normalisation stability policy,
  upgrading the data rock cannot change the result of normalising a string made of characters that
  the older version already assigned. Two processes on different Unicode versions disagree only on
  strings that contain a code point assigned in the newer version and not in the older one; in the
  older process that code point is unassigned (class 0, no decomposition) and passes through
  unchanged. No process-wide state, cache or stored value depends on the version, so a rolling
  upgrade needs no coordination. This property is documented in the package README.
- **No runtime override mechanism.** There is no configuration key, environment variable, API or
  `package.loaded` convention to substitute the tables at run time: the version in use is the
  installed `hecate-unicode-data`, and `unicode.unicode_version` reports it. The only way to change it is
  to install another rock version.

### Error classes

Chosen at implementation (`packages/unicode/src/hecate/unicode/errors.lua`) and listed in the error
catalogue ([object-model.md](../architecture/object-model.md), "Errors"; the generated page of error
codes is produced from the sources by `gen-error-codes`). The root of the package extends `core.Error`
(ADR 0018); the two others extend it.

| Code | Class | Parent | Raised when |
|---|---|---|---|
| `hecate.unicode.UnicodeError` | `UnicodeError` | `core.Error` | Root of the failures of the Unicode algorithms; callers that do not care which one failed catch it. |
| `hecate.unicode.InvalidUtf8Error` | `InvalidUtf8Error` | `UnicodeError` | A string is not well-formed UTF-8 (Unicode Standard 3.9, Table 3-7). `context.position` is the 1-based byte position of the first invalid byte. |
| `hecate.unicode.DataFormatError` | `DataFormatError` | `UnicodeError` | The installed `hecate-unicode-data` has a table `format` that this version of `hecate-unicode` does not know. `context` holds `format`, `supported` and `unicode_version`. |

### Data, generator and tests

- **Source.** The UCD files of one pinned Unicode version: `UnicodeData.txt` (canonical combining
  class, decomposition mappings), `DerivedNormalizationProps.txt` (the property
  `Full_Composition_Exclusion`, which already contains the singletons, the non-starter
  decompositions and the script-specific exclusions of `CompositionExclusions.txt`; that file is
  therefore not needed, and the generator reads it only to cross-check if the owner wants a
  belt-and-braces test). Hangul syllables are not in the tables.
- **Generator.** A new task `gen-unicode` (catalogue in `automation.md`, with `--check` that fails
  if the committed tables differ from the generated ones, like the other `gen-*` tasks) reads the
  pinned files from `.hecate/fixtures/unicode-data/` (fetched, not vendored) and writes
  `packages/unicode-data/src/hecate/unicode_data/*.lua`, committed, each file starting with the
  Unicode License v3 notice and the UCD version and file names. Tables: combining classes by code
  point range, the fully expanded canonical decomposition of each decomposable code point, and the
  primary composition pairs (those not excluded). The split into several modules, loaded lazily
  (a decomposition table is large), is chosen at implementation after measuring load time and
  memory; it is an internal layout covered by `format`.
- **Pinning.** The Unicode version and the SHA-256 of each input file are pinned in the generator
  configuration. `fetch-fixtures` today downloads with git at a pinned commit; the UCD is
  published by version at `https://www.unicode.org/Public/<version>/ucd/`, whose files do not
  change once published, so `fetch-fixtures` gains a second kind of entry (`url` and `sha256`)
  besides `repository` and `commit`. If a git mirror of the UCD at a tagged commit is preferred,
  a `repository` entry is used instead; the implementation step picks one and notes the domain
  needed in `tools/cloud/README.md`.
- **Conformance.** `NormalizationTest.txt` of the same version is downloaded by `fetch-fixtures
  unicode`, **not vendored** (as the CommonMark specification is not), declared in
  `packages/unicode/tests/external.lua`. A test runs every line of every part (including the
  `@Part1` character-by-character part) and requires 100% of the NFC and NFD columns, plus
  idempotence. Without the fixture the suite skips locally and fails in CI. Hangul and reordering
  also have unit tests of their own that do not need the fixture.
- **Nightly check.** `nightly.yml` gains a job `unicode-version` that reads the version of
  `https://www.unicode.org/Public/UCD/latest/ReadMe.txt`, compares it with the pinned one, and
  fails when a newer Unicode version exists, so that the owner learns of the release within a day.
  The failure is informational (the nightly workflow does not gate pull requests). It does not
  regenerate or publish anything: updating is a human step (regenerate with `gen-unicode`,
  conformance, new rock revision). This ADR specifies the job; it is implemented with the packages.

### Licence and notices

- The generated tables are **third-party material** (derived from the UCD), under the **Unicode
  License v3** (`Unicode-3.0`). `THIRD_PARTY_NOTICES` gets a section with the notice, the source
  files and the Unicode version; every generated file carries the notice in its header. The rockspec
  of `hecate-unicode-data` declares `Unicode-3.0` and ships the licence text; `hecate-unicode` and
  the generator are MIT. `check-licenses` knows both identifiers. The licence is permissive and
  compatible with the MIT framework.
- No new Lua rock or C library is added: the only new third-party material is data, covered by this
  ADR.

### Publishing

Publishing a rock is an owner gate (CLAUDE.md). That includes every Unicode data revision: the
release process produces the rock, the owner publishes it. The monorepo split (ADR 0017) creates
the read-only mirror `hecate-framework/hecate-unicode-data` like any other package; its tag is the
Unicode version (`v18.0.0`) and not the framework version, which the `split` and `release` tasks
must handle for this one package.

### What would tip towards `luautf8` (or a native module)

This decision assumes the need is normalisation of short strings (ids, path segments, names). The
balance changes if Hecate needs **grapheme-cluster length or segmentation** (truncating a string to
N user-perceived characters, text width) or **full case folding and case mapping** (caseless
comparison of Unicode identifiers, `lower`/`upper` beyond ASCII): those need more tables
(`GraphemeBreakProperty`, `emoji-data`, `CaseFolding`, `SpecialCasing`) and more code, where a
library that already bundles them (luautf8, or a Rust crate under ADR 0021) is then worth its
build cost. If that happens, the algorithms in `hecate.unicode` keep their API and the
implementation can change underneath; a new ADR decides.

## Consequences

- Two packages to scaffold (`/new-package` for each) and a roadmap item before the replacement of
  the Latin table in `hecate.doc.internal.page_id`; `doc` gains the dependency `hecate-unicode`
  (layer 0, lower than `doc`, no cycle). The gaps of OQ-140 are closed by the conformance test
  rather than by a list.
- A generated-data rock to version, build, test and publish on its own schedule, outside the
  lockstep: `check-versions`, `gen-rockspecs`, `check-rockspecs`, the release and split tasks and
  the matrix of CI (`affected`: a change of `unicode-data` affects `unicode`, `doc` and their
  dependants) each need an explicit rule for it.
- The compatibility range between the two rocks is `hecate-unicode-data >= <minimum>`, the data
  `format` integer, and the stability policy; the risk is a future layout change, handled by the
  rule above. A user who pins `hecate-unicode-data` older than the minimum is refused by LuaRocks.
- Memory and start-up cost of the tables are measured at implementation and reported (benchmarks
  if a hot path such as `router` uses normalisation); the tables are loaded on first use.
- NFKC and NFKD, case folding and segmentation are not provided; requests for them reopen the
  trade-off recorded above.
- A rock whose licence differs from the rest of the framework (`Unicode-3.0` for the data) is
  published; the website reference and the READMEs state it.

## Verification

- `check-boundaries`, `check-package-structure` and `gen-dependency-graph` enforce the layer, the
  names (`hecate.unicode_data`) and the absence of cycles; `check-rockspecs` enforces the
  `hecate-unicode-data >= <minimum>` constraint (no `==` and no upper bound) and the exemption of
  the data rock from the lockstep version.
- `gen-unicode --check` in CI: committed tables equal the generated ones from the pinned inputs.
- The conformance test against `NormalizationTest.txt` of the pinned version passes at 100% on the
  three platforms; a test installs the data rock at the minimum version and at a newer revision
  (when one exists) and runs the same suite.
- `check-licenses` and `check-links` cover `THIRD_PARTY_NOTICES` and the notice headers of the
  generated files.
- The nightly job `unicode-version` fails when a newer Unicode version is published.
