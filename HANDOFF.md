<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `net`: TCP/UDP streams, DNS, buffered readers/writers, TLS (after OQ-4).
- status: in-progress            <!-- in-progress | waiting-ci | waiting-owner -->
- lock_until: 2026-10-13T23:30:07Z
- last_update: 2026-10-13T23:30:07Z

## Done

- Claimed. Skipped the website skeleton: blocked on OQ-11 (generator spike not delivered, owner decision pending).

- Step 1: Stream interface, BufferedReader/BufferedWriter, errors, 18 unit tests (pass), README, CHANGELOG, OQ-28/OQ-29.

- Step 2: reactor TCP primitives (tcp.lua, 21 loopback tests pass), OQ-28 resolved, OQ-30/31 added. Also OQ-11 spike report pushed (docs/spikes/OQ-11-doc-tooling.md), owner decision pending.

- Step 3: net TcpStream/TcpListener/connect/listen, reactor.resolve (dns.lua), tests, OQ-32.

- Step 3: net TcpStream/TcpListener/connect/listen, reactor.resolve; TCP/DNS failures raise reactor.TransportError (a NetworkError, owner decision OQ-32 (5)).
- Side track (owner direction 2026-10-13: OQ-11 route 2): first slice of hecate.doc (Markdown renderer, brand theme, search, build of website/en), OQ-33..38. Website skeleton item NOT ticked yet.

## Next steps

1. net: UDP, pipes/Unix sockets, TLS (ADR 0021), net-level resolver API. Doc: LuaLS reference generation, website.yml deploy (GitHub Pages), OQ-34/35 questions, macOS/Windows check of SystemFileSystem.

## Decisions taken (and where they are recorded)

- Branch is `claude/sweet-feynman-benzkb` (imposed by the session), not `claude/relay-net`.

## Doubts and questions for the owner

- OQ-32, OQ-30, OQ-31, OQ-29 items 1 and 5 (buffered-layer choices).

## Commands to re-run

```sh
lua tools/run.lua test net
lua tools/run.lua check-boundaries
```
