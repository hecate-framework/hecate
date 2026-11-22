---
title: Reference
description: The reference of hecate: the generated code reference of each package, the error codes, the configuration keys and the glossary.
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
- [`hecate.openapi`](openapi/index.md): the OpenAPI 3.1 document assembled from the route table, its canonical encoding, lint and breaking-change diff.
- [`hecate.container`](container/index.md): the inversion-of-control container, lifetimes, constructor injection, boot validation and disposal.
- [`hecate.config`](config/index.md): layered configuration validated by schemas, environment variables, secrets and the immutable `Configuration`.
- [`hecate.kernel`](kernel/index.md): the application, feature modules, controllers, route modules, filters, problem details, the supervisor and the listening strategies of multi-process serving.
- [`hecate.test`](test/index.md): the xUnit test framework: cases, suites, fixtures, assertions, the in-process HTTP client, property-based testing and coverage.
- [`hecate`](hecate/index.md): the meta-module that re-exports the framework surface for applications, and the type names that annotate them.
- [`hecate.unicode`](unicode/index.md): Unicode normalisation of UTF-8 strings, NFC and NFD, and the Unicode version in use.
- [`hecate.unicode_data`](unicode-data/index.md): the generated Unicode Character Database tables behind `hecate.unicode`, versioned by the Unicode version.
- [`hecate.doc`](doc/index.md): the documentation generator and static site builder, and the generation of a project's documentation.

Two pages are generated from the sources and the specifications:

- [Error codes](error-codes.md): every error class, its stable code, its parent and the values of
  `context.reason`.
- [Configuration keys](configuration-keys.md): the keys every configuration declares, their type,
  default, allowed values, environment variable and meaning.

Hand-written pages:

- [Schema keywords and formats](schema-keywords-and-formats.md): every constructor and option of `hecate.schema`, the
  JSON Schema keyword it emits, the supported `format` values and the violation codes.
- [Project documentation](project-documentation.md): the pages generated for a user project, the LuaLS meta files, the theme extension points and `llms.txt`.
- [Theme tokens](theme-tokens.md): every custom property a project can override (colours in light and dark, highlighting, fonts, radii, spacing, sidebar width) and how to ship its own fonts.

The [glossary](glossary.md) defines the vocabulary used everywhere.
