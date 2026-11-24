# 0028 — sha256 in the CLI: the `digest` rock behind a one-line seam

- **Status:** Accepted
- **Date:** 2026-11-14
- **Deciders:** project owner (accepted by the project owner, 2026-11-14, on pull request #200)
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
| `digest` 0.0.1 (osch) | C, one source file plus two vendored cores, MIT AND BSD-3-Clause | correct, 16 MB in 0.07 s, streams, MD5 and SHA-2 and HMAC, no other rock; built by hand from the raw sources (the rockspec downloads a GitHub archive, blocked in the cloud environment); 1741 of its own assertions pass, 1 check fails because its fixture directory could only be partly fetched |
| `lua-resty-crypto` | LuaJIT `ffi` over OpenSSL, no licence declared | cannot run on PUC Lua 5.5 |
| `lua-hashings` | no listing for Lua 5.5 | its 5.5 successor is `lua-hashings-and-nums` (above) |
| `lua-hashings-and-nums` 1.0.3 | pure Lua, MIT | correct, about 50 s per MB |
| `sha2` 0.2.0 | C for Lua 5.1 | does not compile |
| `lsha2` 0.1 | Lua 5.1/5.2, GPL-3 | licence excludes it |

## Options considered

1. **`plc`** (`plc.sha2`, from Roberto Ierusalimschy's Lua implementation). Embeds as Lua source, nothing to
   compile on three platforms; one-shot only; about 2.6 MB/s, so an 825 KB toolchain archive takes about 0.3 s.
2. **`digest`.** Fast, streams, also MD5, SHA-384/512 and HMAC; one C file (it includes the two hash cores) to link
   into the embedded interpreter for each of the six targets, no other rock. Compiled here with GCC on Linux only;
   macOS and MSVC were not tried.
3. **`hmac`.** As fast, also provides HMAC; a C module to link in, plus three build-time rocks (`configh`,
   `lauxhlib`, `luarocks-build-hooks`).
4. **A vendored C implementation** (as yyjson is vendored): no rock, but code to maintain and audit.
5. **System tools** (`sha256sum`, `shasum`, `certutil`): nothing embedded, three different command lines and
   outputs to parse, and a tool that may be absent.

## Decision

- The CLI uses `digest` for sha256 (option 2). `plc` (option 1, pure Lua) is the known alternative, not a fallback in the
  code: the CLI has one backend, and the project switches to `plc` only if `digest` fails on a platform, in a later
  release (clarified by the project owner, 2026-11-24; the ADR stays Accepted). The prototype keeps a `plc` backend to show
  that the switch is small; the CLI itself has none.
- `digest` is a dependency of the CLI only (lock-file checksums, downloaded archives). It is not a general
  cryptography dependency: cryptography and hashing for security purposes belong to the `security` package, which is
  to depend on `luasodium` (owner direction of 2026-11-14, see OQ-45).
- It reaches it only through `hecate.cli.digest` (`cli_digest` in the prototype), whose interface is `sha256(data)` and `sha256_file(path)`, both
  returning 64 lowercase hexadecimal characters. The rock is chosen in **one** module (the backend), so that
  switching to `digest`, `hmac` or another rock changes that module and the rockspec dependency, and no caller.
- The prototype in [`docs/spikes/OQ-13/`](../spikes/OQ-13/) (`cli_digest.lua`, `digest_backend.lua`,
  `digest_backend_plc.lua`, `digest_backend_hmac.lua`, `digest_backend_digest.lua`, `digest_test.lua`) shows the
  shape; the three backends pass the same contract test, and `digest_backend.lua` selects `digest`.
- Not decided here: replacing `digest` by `plc`, `hmac` or another rock if a risk below materialises. The seam makes
  that a small change.

## Consequences

- `hecate-cli` depends on the `digest` rock (rockspec updated with this ADR). `THIRD_PARTY_NOTICES` records it when it
  is vendored or compiled into the executable (the file lists vendored material, not rock dependencies): MIT for
  the binding, BSD-3-Clause for `sha2.c` (a notice obligation), MIT for `md5.c` (the rock ships
  `LICENSE-THIRD-PARTY`).
- Files are streamed in chunks (`digest.new("sha256")`), so large archives need no extra memory.
- Risks, accepted with the seam as the mitigation: the rock is young (24 days on 2026-11-14, one maintainer, 215
  downloads); if it is abandoned, its single C file and two cores can be vendored (as yyjson is) or the backend
  switched to `plc`. Its README claims CI on macOS and on Windows (MSVC and MinGW) for Lua 5.5, which we have not
  verified at the time of drafting; the check was done on 2026-11-14 (throwaway workflow of the pull request, result in
  the [spike report](../spikes/OQ-13-standalone-executable.md)): the rock installs through LuaRocks and passes its own
  suite on Linux x86_64 and arm64, macOS arm64 and x86_64 and Windows (MSVC), with `plc` as the tested alternative. It was compiled here with GCC on Linux only, and its own suite was run with part of its fixtures.
- The contract test of the seam runs against every backend present, so a switch is checked by the same vectors.

## Verification

- A unit test of `hecate.cli.digest` with the vectors of the prototype (empty string, `abc`, one million `a`) and
  a file case, run for each backend.
- When the CLI is implemented, a review rule (or a `check-boundaries` rule, to be added then) keeps the rock required
  in the backend module only; no such check exists today.
