<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `net`: TCP/UDP streams, DNS, buffered readers/writers, TLS (after OQ-4).
- status: in-progress            <!-- in-progress | waiting-ci | waiting-owner -->
- lock_until: 2026-10-13T23:49:49Z
- last_update: 2026-10-13T22:19:49Z

## Done

- Claimed. Skipped the website skeleton: blocked on OQ-11 (generator spike not delivered, owner decision pending).

## Next steps

1. Read docs/architecture/concurrency.md, packages/net/README.md, ADR 0021 (rustls); plan steps (TCP, UDP, DNS, buffered I/O, then TLS).

## Decisions taken (and where they are recorded)

- Branch is `claude/sweet-feynman-benzkb` (imposed by the session), not `claude/relay-net`.

## Doubts and questions for the owner

## Commands to re-run

```sh
```
