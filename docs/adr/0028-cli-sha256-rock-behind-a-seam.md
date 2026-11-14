# 0028 — sha256 in the CLI: the `plc` rock behind a one-line seam

- **Status:** Proposed
- **Date:** 2026-11-14
- **Deciders:** project owner
- **Packages:** cli
- **Related:** [ADR 0009](0009-project-manifest.md) (`hecate.lock` carries checksums), [ADR 0010](0010-self-contained-cli-and-managed-toolchains.md), [spike OQ-13](../spikes/OQ-13-standalone-executable.md), OQ-13

## Context

`hecate.lock` records checksums, and `hecate toolchain install` must verify downloaded archives. The Lua
standard library has no sha256, and the `hecate` executable embeds only what the CLI needs (OQ-13, owner
decision of 2026-11-14). The rule of the project is to prefer an existing rock to code written from scratch
(owner remark of 2026-11-14), and a new third-party dependency needs an ADR and the owner's approval.

Candidates were installed on Lua 5.5.1 and checked against `sha256sum` on `abc` and on 16 MB of data
([spike OQ-13](../spikes/OQ-13-standalone-executable.md), table "sha256"):

| Rock | Kind, licence | Result on Lua 5.5 |
|---|---|---|
| `plc` 0.5 | pure Lua, MIT | correct, 16 MB in 6.1 s |
| `hmac` 0.4.1 | C, MIT | correct, 16 MB in 0.07 s; builds with `configh`, `lauxhlib`, `luarocks-build-hooks` |
| `lua-hashings-and-nums` 1.0.3 | pure Lua, MIT | correct, about 50 s per MB |
| `sha2` 0.2.0 | C for Lua 5.1 | does not compile |
| `lsha2` 0.1 | Lua 5.1/5.2, GPL-3 | licence excludes it |

## Options considered

1. **`plc`** (`plc.sha2`, from Roberto Ierusalimschy's Lua implementation). Embeds as Lua source, nothing to
   compile on three platforms; one-shot only; about 2.6 MB/s, so an 825 KB toolchain archive takes about 0.3 s.
2. **`hmac`.** Fast, streams, also provides HMAC; a C module to link into the embedded interpreter for each of
   the six targets, plus three build-time rocks.
3. **A vendored C implementation** (as yyjson is vendored): no rock, but code to maintain and audit.
4. **System tools** (`sha256sum`, `shasum`, `certutil`): nothing embedded, three different command lines and
   outputs to parse, and a tool that may be absent.

## Decision

- The CLI uses `plc` for sha256 (option 1).
- It reaches it only through `hecate.cli.digest`, whose interface is `sha256(data)` and `sha256_file(path)`, both
  returning 64 lowercase hexadecimal characters. The rock is chosen in **one** module (the backend), so that
  switching to `hmac` or another rock changes that module and the rockspec dependency, and no caller.
- The prototype in [`docs/spikes/OQ-13/`](../spikes/OQ-13/) (`digest.lua`, `digest_backend.lua`,
  `digest_backend_plc.lua`, `digest_backend_hmac.lua`, `digest_test.lua`) shows the shape; both backends pass the
  same contract test.
- Not decided here: replacing `plc` by `hmac` if archives grow or hashing shows up in a measurement. The seam
  makes that a small change.

## Consequences

- `hecate-cli` depends on `plc` when this ADR is accepted (the rockspec is not changed before), and
  `THIRD_PARTY_NOTICES` records it (MIT, with the Ierusalimschy notice carried by the rock).
- Files are read whole before hashing with `plc` (no streaming); acceptable for toolchain archives and lock
  data, to be revisited with the `hmac` backend if larger inputs appear.
- The contract test of the seam runs against every backend present, so a switch is checked by the same vectors.

## Verification

- A unit test of `hecate.cli.digest` with the vectors of the prototype (empty string, `abc`, one million `a`) and
  a file case, run for each backend.
- When the CLI is implemented, a review rule (or a `check-boundaries` rule, to be added then) keeps the rock required
  in the backend module only; no such check exists today.
