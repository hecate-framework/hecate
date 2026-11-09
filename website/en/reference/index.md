---
title: Reference
description: The reference of hecate: the generated code reference of each package and the glossary.
hecate: "0.x"
lua: "5.5"
order: 0
---

# Reference

The code reference is generated from the annotations of the source. One section exists per
documented package.

- [`hecate.core`](core/index.md): object model, errors.
- [`hecate.reactor`](reactor/index.md): coroutines, futures, structured concurrency, timers,
  signals, processes, file system, TCP, UDP, pipes and name resolution.
- [`hecate.net`](net/index.md): streams, TCP, UDP, pipes, name resolution, TLS and the buffered
  layer.
- [`hecate.json`](json/index.md): encoding, decoding, markers and errors.
- [`hecate.log`](log/index.md): structured records, RFC 5424 severities, context and sinks.
- [`hecate.http`](http/index.md): the HTTP/1.1 server and client, messages, content streams, forms and problem details.
- [`hecate.router`](router/index.md): the radix-tree router, path templates, matching, reverse routing and route table errors.
- [`hecate.schema`](schema/index.md): refinement types, validation, coercion and JSON Schema emission.
- [`hecate.container`](container/index.md): the inversion-of-control container, lifetimes, constructor injection, boot validation and disposal.

The [glossary](glossary.md) defines the vocabulary used everywhere.
