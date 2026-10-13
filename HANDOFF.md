<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `net`: TCP/UDP streams, DNS, buffered readers/writers, TLS (after OQ-4).
- status: waiting-owner            <!-- in-progress | waiting-ci | waiting-owner -->
- lock_until: 2026-10-13T22:22:51Z
- last_update: 2026-10-13T22:22:51Z

## Done

- Claimed. Skipped the website skeleton: blocked on OQ-11 (generator spike not delivered, owner decision pending).

- Step 1: Stream interface, BufferedReader/BufferedWriter, errors, 18 unit tests (pass), README, CHANGELOG, OQ-28/OQ-29.

## Next steps

1. BLOCKED on OQ-28: owner chooses (a) suspending TCP/UDP/DNS primitives in reactor (recommended, keeps luv confined per ADR 0002) or (b) ADR amendment letting net use luv. Then: TcpStream/TcpListener, UDP, DNS, Unix sockets/pipes, TLS (ADR 0021).

## Decisions taken (and where they are recorded)

- Branch is `claude/sweet-feynman-benzkb` (imposed by the session), not `claude/relay-net`.

## Doubts and questions for the owner

- OQ-28 (blocker above). OQ-29 items 1 and 5 (buffered-layer choices).

## Commands to re-run

```sh
lua tools/run.lua test net
lua tools/run.lua check-boundaries
```
