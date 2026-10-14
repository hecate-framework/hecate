<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `net`: TCP/UDP streams, DNS, buffered readers/writers, TLS (after OQ-4).
- status: in-progress            <!-- in-progress | waiting-ci | waiting-owner -->
- lock_until: 2026-10-14T20:15:00Z
- last_update: 2026-10-14T18:45:00Z

## Done

- Claimed. Skipped the website skeleton: blocked on OQ-11 (generator spike not delivered, owner decision pending).

- Step 1: Stream interface, BufferedReader/BufferedWriter, errors, 18 unit tests (pass), README, CHANGELOG, OQ-28/OQ-29.

- Step 2: reactor TCP primitives (tcp.lua, 21 loopback tests pass), OQ-28 resolved, OQ-30/31 added. Also OQ-11 spike report pushed (docs/spikes/OQ-11-doc-tooling.md), owner decision pending.

- Step 3: net TcpStream/TcpListener/connect/listen, reactor.resolve (dns.lua), tests, OQ-32.

- Step 3: net TcpStream/TcpListener/connect/listen, reactor.resolve; TCP/DNS failures raise reactor.TransportError (a NetworkError, owner decision OQ-32 (5)).
- Side track (owner direction 2026-10-13: OQ-11 route 2): first slice of hecate.doc (Markdown renderer, brand theme, search, build of website/en), OQ-33..38. Website skeleton item NOT ticked yet.

- Side track: owner answered the OQ-11 questions (route a, GFM via dependencies, wasm). Recorded in ADR 0012 / OQ-33..38; spike OQ-39 + proposed ADR 0022 (comrak via mlua, syntect, Pagefind, own OpenAPI, wasm Lua); reference generator from the LuaLS export (OQ-40), `---@class` convention in coding-standards.md; body H1 is the page title.
- Step 4: UDP (reactor.udp_bind/UdpSocket, net.bind_udp/UdpSocket), loopback tests pass locally (luv installed with `luarocks --tree .hecate/rocks install luv`).
- Step 5: pipes/Unix sockets (reactor.pipe_connect/pipe_listen, net.connect_pipe/listen_pipe), tests, docs. Windows named-pipe behaviour verified only by CI.

- Run 2026-10-14T06:4x: resumed (CI was green on 3 platforms, lock expired). Starting step 6: TLS native module.

- Step 6: TLS (rustls via mlua): packages/net/native crate, net.tls/TlsStream/connect_tls, tests (tests/integration/tls_test.lua, fixtures), `build-native` task, OQ-41. Not committed by the subagent.
- CI work needed (workflows not edited): install a Rust toolchain, run `lua tools/run.lua build-native` before `test net` on the three platforms (Windows: LUA_LIB_NAME=lua55, LUA_LIB, LUA_INC; macOS flags are in native/.cargo/config.toml), cache `packages/net/native/target`, add cargo-deny/audit; the TLS tests skip silently when the module is missing, so CI should assert that it is built. LuaRocks `rust-mlua` build type unverified (OQ-41 (7)).

- Step 7: ci.yml builds the Rust native module (Linux/macOS via build-native, Windows with LUA_LIB_NAME=lua55/LUA_LIB/LUA_INC) when net is affected and asserts the artifact exists. Verified locally on Linux only; macOS/Windows verified by CI. Still missing: cargo cache is keyed on Cargo.lock only, cargo-deny/audit not added.

- Step 8: found that the ci.yml `plan` job had no `lua` (command not found, hidden by `|| true`), so PACKAGES was always empty and CI only ran tools tests: every earlier green run verified no package. Fixed by bootstrapping the toolchain in `plan` and removing `|| true`. Next CI run is the first real one for net/reactor/core; expect possible genuine failures (native build, Windows).

- Step 9 (CI, Windows): fixed the SIGPIPE guard (luv raises on Windows), added .gitattributes (LF; CRLF checkout broke the examples and doc golden tests), made wait_signal close its handle when luv raises, platform-tolerant errno / payload size in two TCP tests. macOS test races fixed. Windows fixes unverified until CI runs; remaining Windows differences (ECANCELED on reset peers, back-pressure size) are guesses.

- CI is green on the three platforms at 5a32d4a with real per-package tests and the native TLS build. Not yet done: /review-package pass, cargo-deny/audit in CI, net-level resolver API, website reference pages, roadmap tick.

- Run 2026-10-14T12:4x: resumed (CI green, lock expired). Step 10: net.resolve added (net/dns.lua, test, README, CHANGELOG). Remaining: /review-package, cargo-deny/audit in CI, roadmap tick.

- Run 2026-10-14T18:4x: resumed (CI green at adadd5d, lock expired), pushed to the session branch `claude/sweet-feynman-ebc1nh`. /review-package net done (7 reviewers, no blockers). Fixed: TlsError wrapping of native calls, TlsStream:is_closed, handshake no-progress, closed BufferedReader raises, limit/max validation, poisoned writer raises fresh NetworkError(cause), HECATE_REQUIRE_NATIVE in CI, stale docs, "task" wording. Roadmap NOT ticked: review backlog below.

## Review backlog (net), by severity

Medium:
- cargo-deny/audit: no `deny.toml`, no CI job, no dependabot cargo entry (ADR 0021 requires it); Proposed ADR for the transitive crate tree and trust store (OQ-41 (1)).
- Limits: `TlsStream:read(max)` allocation unbounded in native `lib.rs:113`; `BufferedReader:read_exact` unbounded and O(n^2) concatenation; no default handshake deadline for `tls.connect`/`tls.accept` (document or add).
- API: `Stream` interface should list `__close`, `shutdown`, `is_closed`, `reader`, `writer` (shared trait instead of 3 copies); `net.connect` hides earlier address failures; `listen("localhost")` binds first address only, `bind_udp` has no `options`/`family`, `send_to` numeric only; improve `connect_tls` ca_pem message; wrap native error text with stable message and context; validate TLS config type; BufferedReader/Writer unknown options.
- Tests: TLS failure paths lack handle-leak assertions and server-side outcomes; missing expired/self-signed/IP-SAN/non-TLS peer/handshake stall cases; real sleeps for synchronisation (flaky risk on macOS/Windows); racy reset test; no write back-pressure/cancel test; close during pending read/write; fixture expiry (100 years, fine) ; property test for chunking.
- Cross-platform: macOS link flags via inline RUSTFLAGS (use build.rs), Windows build asserts (`lua55.lib`, `rustup default stable`, pin target), `cp`/`copy` quoting in build_native.lua, cargo cache key without rustc version/rust-toolchain.toml, AF_UNIX path length on macOS (use uv.os_tmpdir, add pid), `localhost` in UDP/reactor tests, keepalive EINVAL/ENOTCONN race at accept.
- TLS 1.2 enabled: record the decision in OQ-41 or restrict to 1.3.
Low: DNS host length/result cap, zeroize key temporaries, session ticket/0-RTT explicitness, README gaps (UdpSocket methods, "Layout" heading), EndOfStreamError message detail, glossary entries for `record`/`stream`/`back-pressure`, rockspec cannot ship TLS (OQ-41 (7)).

## Next steps

1. net: work through the review backlog (cargo-deny first), then tick the roadmap item and mark the PR ready. Doc: owner decision on ADR 0022 (native code in doc), website.yml deploy (GitHub Pages) with gen-reference --require, class-method param docs, OQ-34/35 questions, macOS/Windows check of SystemFileSystem.

## Decisions taken (and where they are recorded)

- Branch is `claude/sweet-feynman-benzkb` (imposed by the session), not `claude/relay-net`.

## Doubts and questions for the owner

- OQ-32, OQ-30, OQ-31, OQ-29 items 1 and 5 (buffered-layer choices).

## Commands to re-run

```sh
lua tools/run.lua test net
lua tools/run.lua check-boundaries
```
