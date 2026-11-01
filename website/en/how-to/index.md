---
title: How-to guides
description: Recipes that solve one problem with hecate, each written for hecate 0.x and Lua 5.5.
hecate: "0.x"
lua: "5.5"
order: 0
---

# How-to guides

Each guide solves one problem and assumes you know the basics. For the reasons behind a recipe,
read the matching page of the [explanation](../explanation/index.md) section.

## Network and processes

- [Connect and serve over TCP](connect-and-serve-over-tcp.md): connect, accept connections,
  read and write lines, half-close, resolve names.
- [TLS client and server](tls-client-and-server.md): trust the system store or a private
  authority, serve TLS, require client certificates, read TLS errors.
- [Deadlines and cancellation on streams](deadlines-and-cancellation.md): bound a connect, a read
  or an accept, and know what a cancelled operation leaves behind.
- [UDP, Unix sockets, named pipes and DNS](udp-pipes-and-dns.md): the transports other than TCP.
- [Run child processes and pass connections between processes](run-processes-and-pass-connections.md):
  `run_process`, `spawn`, the message pipe and handing a connection to a child.

## HTTP

- [Serve HTTP](serve-http.md): start a server, write a handler, answer with JSON and problem
  details, set cookies, shut down.
- [Stream HTTP content](stream-http-content.md): read request content chunk by chunk and stream
  a response.
- [Use the HTTP client](use-the-http-client.md): requests, pooled connections, redirects,
  deadlines and failures.
- [Handle forms and multipart](handle-forms-and-multipart.md): urlencoded forms, uploads and
  untrusted filenames.
- [Set limits, timeouts and TLS on the HTTP server](http-limits-timeouts-and-tls.md): every
  bound, its default, and HTTPS.

## Performance

- [Measure performance](measure-performance.md): run the TCP echo benchmark, read its figures and
  compare a change with its base.

## Data

- [Encode and decode JSON](encode-and-decode-json.md): integers and floats, `null`, empty
  arrays, canonical output and decode errors.
- [Log structured records](log-structured-records.md): severities, context, sinks, secrets and
  volume limits.
