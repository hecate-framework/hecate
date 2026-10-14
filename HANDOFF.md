<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `net`: TCP/UDP streams, DNS, buffered readers/writers, TLS (after OQ-4).
- status: in-progress            <!-- in-progress | waiting-ci | waiting-owner -->
- lock_until: 2026-10-14T02:15:00Z
- last_update: 2026-10-14T00:45:00Z

## Done

- Claimed. Skipped the website skeleton: blocked on OQ-11 (generator spike not delivered, owner decision pending).

- Step 1: Stream interface, BufferedReader/BufferedWriter, errors, 18 unit tests (pass), README, CHANGELOG, OQ-28/OQ-29.

- Step 2: reactor TCP primitives (tcp.lua, 21 loopback tests pass), OQ-28 resolved, OQ-30/31 added. Also OQ-11 spike report pushed (docs/spikes/OQ-11-doc-tooling.md), owner decision pending.

- Step 3: net TcpStream/TcpListener/connect/listen, reactor.resolve (dns.lua), tests, OQ-32.

- Step 3: net TcpStream/TcpListener/connect/listen, reactor.resolve; TCP/DNS failures raise reactor.TransportError (a NetworkError, owner decision OQ-32 (5)).
- Side track (owner direction 2026-10-13: OQ-11 route 2): first slice of hecate.doc (Markdown renderer, brand theme, search, build of website/en), OQ-33..38. Website skeleton item NOT ticked yet.

- Side track: owner answered the OQ-11 questions (route a, GFM via dependencies, wasm). Recorded in ADR 0012 / OQ-33..38; spike OQ-39 + proposed ADR 0022 (comrak via mlua, syntect, Pagefind, own OpenAPI, wasm Lua); reference generator from the LuaLS export (OQ-40), `---@class` convention in coding-standards.md; body H1 is the page title.
- Step 4: UDP (reactor.udp_bind/UdpSocket, net.bind_udp/UdpSocket), loopback tests pass locally (luv installed with `luarocks --tree .hecate/rocks install luv`).

## Next steps

1. net: pipes/Unix sockets, TLS (ADR 0021), net-level resolver API. Doc: owner decision on ADR 0022 (native code in doc), website.yml deploy (GitHub Pages) with gen-reference --require, class-method param docs, OQ-34/35 questions, macOS/Windows check of SystemFileSystem.

## Decisions taken (and where they are recorded)

- Branch is `claude/sweet-feynman-benzkb` (imposed by the session), not `claude/relay-net`.

## Doubts and questions for the owner

- OQ-32, OQ-30, OQ-31, OQ-29 items 1 and 5 (buffered-layer choices).

## Commands to re-run

```sh
lua tools/run.lua test net
lua tools/run.lua check-boundaries
```
