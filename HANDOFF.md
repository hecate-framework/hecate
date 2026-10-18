<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `net`: TCP/UDP streams, DNS, buffered readers/writers, TLS (after OQ-4).
- status: in-progress            <!-- in-progress | waiting-ci | waiting-owner -->
- lock_until: 2026-10-18T14:43:00Z
- last_update: 2026-10-18T13:13:00Z

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

- Run 2026-10-14T21:4x: resumed; CI green on adadd5d (3 platforms). The session imposed branch claude/sweet-feynman-ucrp15 (PR #19 head is claude/sweet-feynman-benzkb); no code change this run, only this note. cargo-deny/audit left undone: needs a new CI action (supply-chain choice, pin by SHA) and a licence policy, which I cannot verify locally.

- Run 2026-10-18 (owner: fix the /review-package net findings, OQ-11 resolved, glossary entries stream/back-pressure/half-close approved, prose "task" -> "coroutine" and `live_tasks` -> `live_coroutines`, native module ships inside the rock): OQ-11 moved to Resolved; TLS wrapper fixes (record order mutex, is_closed, stall detection, argument validation, early-error ownership), native `read` clamp, BufferedReader (limit validation, `read_exact` limit, linear chunks, read after close raises), Rust lints and no `logging` feature, pinned toolchain (rust-toolchain.toml), `HECATE_REQUIRE_TLS`, clippy/fmt in CI; docs drift (OQ-28 row, OQ-42, OQ-30 mark, net CLAUDE.md, reactor README/init.lua, concurrency.md "Transport"); rock binaries spike (docs/spikes/OQ-41-rock-binaries.md, ADR 0021, OQ-41 (7), roadmap).

- Same run, later steps: early port validation, never-empty `net.resolve`, Unix socket path limit (OQ-42), typecheck fixes (CI run 82 failed on 3 LuaLS warnings; LuaLS 3.19.1 is installed in the git-ignored `spikes/luals`, run `PATH=$PWD/spikes/luals/bin:$PATH lua tools/run.lua typecheck`), `net` tests de-flaked (channels and joins instead of sleeps, tcp_test.lua and tls_test.lua), new tests (mutual TLS rejection, inconsistent options, port validation, path length).

- Merged `claude/sweet-feynman-ebc1nh` into this branch (2026-10-18). That branch, pushed by the relay run of 2026-10-14T18:4x, carried a full /review-package net (7 reviewers) and fixes that never reached this PR (the session had imposed another branch). Kept from it: `call()` wrapper so every native session failure is a `TlsError`, a poisoned `BufferedWriter` raises a fresh `NetworkError` with the original as `cause` (a stored cancellation must not be re-raised at another caller), `read_some(max)` validation, the architecture overview TLS row. Superseded by this branch's versions: stall detection, `is_closed`, closed reader, `HECATE_REQUIRE_NATIVE` (now `HECATE_REQUIRE_TLS`, set only when `net` is affected). Its extra backlog, still open: a shared `Stream` trait instead of three copies of `__close`/`shutdown`/`is_closed`/`reader`/`writer`; `net.connect` hides the earlier address failures; `listen("localhost")` binds the first address only; DNS host length and result cap; dependabot entry for cargo; README gaps (UdpSocket methods).

- OQ-8 (owner request 2026-10-18, multi-process by design, Linux never compromised): spike on three platforms (docs/spikes/OQ-8-multi-process.md, script and luv patch in docs/spikes/OQ-8/), Proposed ADR 0023 (two strategies: `reuseport` on Linux, `round_robin` elsewhere; the shared listening socket balanced nowhere and was dropped), OQ-43 (TCP `SO_REUSEPORT` from Lua: luv sets it for UDP only), glossary primary/worker/listening strategy, concurrency.md "Workers", roadmap item for the `reactor` primitives. This is a design deliverable on this PR; no `spawn`/`ipc` code yet (roadmap, after the owner promotes ADR 0023). A localised luv checkout and build live in the git-ignored `spikes/OQ-8` and `spikes/luals`.

- 2026-10-18, later: ADR 0023/0024 Accepted, OQ-8/41/44 resolved, rustls 0.23.46, fair OQ-8 measurement (`reuseport` is an optimisation: OQ-43 not urgent), net-review decision-free tests and fixes: property tests of the reader found and fixed a real bug (`read_until` limit with a split multi-byte delimiter), `TlsError` `context.reason`, expired/ALPN/IP SAN/stalled handshake tests, handle-leak check around every TLS test, slow-peer test, fixtures for the expired certificate.

## Next steps

1. Check CI on the head commit (three platforms); fix before anything else.
2. Net-review findings still open and needing the owner: argument order of `UdpSocket:send_to` (data first today, `connect` takes host first), a one-call server-side TLS form (`listen_tls`) versus the documented two-step `tls.accept(listener:accept(), config)`, TLS error subclasses instead of `context.reason`. Decision-free and not done: `bind_udp` options/`family`, `net.connect` keeps only the last address failure (attach the attempts), shared `Stream` trait instead of three copies, native crate unit tests (in-memory client and server), cargo-fuzz targets, tighten the Windows errno tolerance per platform, README gaps (UdpSocket methods).
3. Other items: de-flake the reactor tests (reactor/tests/integration/tcp_test.lua ~220, 261, 342; udp_test.lua ~54, 68); `security.yml` with cargo-deny and cargo audit (owner choices: licence allowlist, action pinning, see the notes in the conversation: `ring` needs a clarification, `webpki-root-certs` is in `Cargo.lock` only for a target we do not build, restrict `targets` to the three triples); website reference pages for `net`; the `reactor` primitives of ADR 0023 (`spawn`, `ipc`, handle passing).
4. Then /review-package net again, tick the roadmap item, delete this file, mark PR #19 ready.

## Decisions taken (and where they are recorded)

- Branch is `claude/sweet-feynman-benzkb` (imposed by the session), not `claude/relay-net`.

## Doubts and questions for the owner

- OQ-32, OQ-30, OQ-31, OQ-29 items 1 and 5 (buffered-layer choices).

## Commands to re-run

```sh
lua tools/run.lua test net
lua tools/run.lua check-boundaries
```
