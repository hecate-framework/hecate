---
title: Explanation
description: The concepts and the reasons behind hecate, written for hecate 0.x and Lua 5.5.
hecate: "0.x"
lua: "5.5"
order: 0
---

# Explanation

These pages explain how hecate works and why it is designed this way. They do not give recipes:
the [how-to guides](../how-to/index.md) do.

- [The transport model](transport-model.md): streams, suspension instead of callbacks,
  back-pressure, half-close, buffering and cancellation.
- [TLS trust and security defaults](tls-trust-and-security.md): why the operating system's
  verifier, what cannot be disabled, and the platform caveats.
- [Multi-process serving](multi-process-serving.md): share-nothing workers, listening strategies
  and the message pipe, and which parts exist today.

The vocabulary is defined in the [glossary](../reference/glossary.md).
