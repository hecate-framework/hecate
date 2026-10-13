<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `net`: TCP/UDP streams, DNS, buffered readers/writers, TLS (after OQ-4).
- status: in-progress            <!-- in-progress | waiting-ci | waiting-owner -->
- lock_until: 2026-10-13T22:42:54Z
- last_update: 2026-10-13T22:42:54Z

## Done

- Claimed. Skipped the website skeleton: blocked on OQ-11 (generator spike not delivered, owner decision pending).

- Step 1: Stream interface, BufferedReader/BufferedWriter, errors, 18 unit tests (pass), README, CHANGELOG, OQ-28/OQ-29.

- Step 2: reactor TCP primitives (tcp.lua, 21 loopback tests pass), OQ-28 resolved, OQ-30/31 added. Also OQ-11 spike report pushed (docs/spikes/OQ-11-doc-tooling.md), owner decision pending.

## Next steps

1. OQ-28 resolved by owner (option a). Next: net TcpStream/TcpListener on reactor.tcp_connect/tcp_listen; then reactor UDP + DNS (host names: tcp_connect is numeric only), pipes, then TLS (ADR 0021). Review OQ-30/OQ-31 (SIGPIPE guard).

## Decisions taken (and where they are recorded)

- Branch is `claude/sweet-feynman-benzkb` (imposed by the session), not `claude/relay-net`.

## Doubts and questions for the owner

- OQ-30, OQ-31, OQ-29 items 1 and 5 (buffered-layer choices).

## Commands to re-run

```sh
lua tools/run.lua test net
lua tools/run.lua check-boundaries
```
