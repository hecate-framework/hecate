# `hecate-websocket`

> WebSocket protocol (RFC 6455) server and client integrated with the kernel.

| | |
|---|---|
| Module | `hecate.websocket` |
| Rock | `hecate-websocket` |
| Layer | Protocol |
| Roadmap phase | 5 |
| Status | planned — no code yet |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`reactor`](../reactor), [`net`](../net), [`http`](../http) |
| Used by | — |
| Native code | none |
| Specification | [roadmap.md](../../docs/roadmap.md) |
| Decisions | — |
| Agent | [`pkg-websocket`](../../.claude/agents/pkg-websocket.md) |
| Repository | read-only mirror `hecate-framework/hecate-websocket`, generated from this directory (ADR 0017) |

## Responsibilities

- handshake, framing, fragmentation, ping/pong, close
- kernel routes for WebSocket endpoints

## Non-goals

- Socket.IO

## Standards and references

- RFC 6455
- RFC 7692 (permessage-deflate)

## Public API

*To be filled during implementation: list every exported class and function with a one-line
description, linking to the generated reference.*

## Layout (once implemented)

```text
src/hecate/websocket/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
```
