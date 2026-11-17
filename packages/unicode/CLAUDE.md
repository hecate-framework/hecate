# Agent context — `hecate.unicode`

You are working inside `packages/unicode`. Read the root `CLAUDE.md` first; this file adds
package-specific context. Specialist agent: `pkg-unicode`.

## Purpose

Unicode normalisation of UTF-8 strings: NFC, NFD, Hangul syllable arithmetic and canonical reordering.

## Read before changing anything

- Decisions: `docs/adr/0032-unicode-normalisation-packages.md`, `docs/adr/0018-error-signalling.md`
- Glossary: `docs/glossary.md` · Coding standards: `docs/architecture/coding-standards.md`
- This package's `README.md` (scope, dependencies, status)

## Boundaries

- Allowed dependencies: `hecate.core`, `hecate.unicode_data`.
  Anything else requires an ADR; `check-boundaries` fails otherwise.
- Native code: none. No I/O. Out of scope: NFKC and NFKD, case mapping, segmentation, collation (ADR 0032).
- The tables are the rock `hecate-unicode-data`: never edit them by hand and never add a way to substitute them at run
  time (no option, variable or `package.loaded` convention).
- If your task needs a change in another package, stop and describe the needed change
  instead of making it (unless the task explicitly spans packages).

## Invariants (must hold after every change)

- `nfc` and `nfd` pass 100% of the NFC and NFD columns of `NormalizationTest.txt` of the pinned Unicode version, plus
  idempotence and the invariance of the code points that Part 1 does not list
- a table `format` that the package does not know is refused with `DataFormatError` before any table is read
- invalid UTF-8 is an `InvalidUtf8Error` (never a silent pass-through); a string with no byte above 0x7F is returned as it is
- the canonical ordering is stable and costs n log n on a long run of marks (no quadratic path on hostile input)
- the Hangul syllables are computed, never looked up
- unassigned code points pass through unchanged, so that an older data rock never changes a string it does not know

Plus, for every change: unit tests for public behaviour, LuaLS annotations on public API
(`---@async` on anything that may suspend), README "Public API" section updated.

## Standards

- Unicode Standard 3.11 and 3.12; UAX #15; cite section numbers in code comments when implementing normative behaviour
