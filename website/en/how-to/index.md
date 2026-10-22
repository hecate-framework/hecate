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

## Data

- [Encode and decode JSON](encode-and-decode-json.md): integers and floats, `null`, empty
  arrays, canonical output and decode errors.
- [Log structured records](log-structured-records.md): levels, context, sinks, secrets and
  volume limits.
