---
description: Run the network benchmarks (TCP echo, plaintext HTTP, JSON through the kernel), read their latency and throughput figures, and compare your working tree with a Git reference.
hecate: "0.x"
lua: "5.5"
order: 7
---

# Measure performance

The repository has network benchmarks that measure the latency and the throughput of a server under load. Use them to
see what a change costs, by comparing your working tree with its base. This guide is written for hecate 0.x and
Lua 5.5. The network scenarios run on Linux and macOS, not on Windows.

## Run the TCP echo scenario

The `tcp-echo` scenario starts an echo server built on `hecate.reactor` and `hecate.net`. It then drives the server
with a load generator written in Lua.

The generator is *open loop*. Each connection is due to send one request per interval. The latency of a request is
measured from the instant it was due, not from the instant it was sent. So a slow server cannot hide its queueing.
This effect is known as coordinated omission.

Raise the limit of open files above the number of connections, then run the scenario:

```sh
ulimit -n 20000
lua tools/run.lua bench tcp-echo --rounds=5 --connections=10000 --rate=5000 --duration=10
```

A round is one run of the server and the generator. The task runs `--rounds` rounds (default 5). For every measure,
it prints the median, the minimum and the maximum over the rounds, and the ratio between the largest and the smallest.
Add `--json` for a machine-readable report.

| Measure | Unit | Meaning |
|---|---|---|
| `throughput` | requests/s | completed requests per second after the warm-up |
| `errors` | connections | connections that failed to open or broke |
| `latency p50`, `p90`, `p99`, `p99.9`, `max` | µs | latency from the due time |

A throughput below `--rate` means that the server, or the generator, is saturated.

## Set the load

The load generator takes these options:

| Option | Meaning | Default of `tcp-echo` |
|---|---|---|
| `--connections` | number of connections | 100 |
| `--rate` | total requests per second, over all connections | 1000 |
| `--duration` | seconds of measurement | 10 |
| `--warmup` | seconds before the measurement starts | 2 |
| `--payload` | bytes of each request | 64 |

## Measure the HTTP stack and the kernel

Two more scenarios measure HTTP/1.1. They use the same kind of open-loop generator. Each connection is a
[persistent connection](../reference/glossary.md#http), kept open for several requests.

- `plaintext`: an `http.Server` action answers `GET /plaintext` with `Hello, World!`. It measures the HTTP stack alone.
- `kernel-json`: a `kernel.Application` with one route answers `GET /json` with `{"message":"Hello, World!"}`. The
  kernel represents the result with the declared response schema and encodes it as JSON. The difference with
  `plaintext` is the cost of routing, dispatch and serialisation.

Both need the native modules of `json` and `http`. Build them once, then run the scenarios:

```sh
lua tools/run.lua build-native json
lua tools/run.lua build-native http
lua tools/run.lua bench plaintext --rounds=5 --connections=100 --rate=5000 --duration=10
lua tools/run.lua bench kernel-json --rounds=5 --connections=100 --rate=5000 --duration=10
```

The HTTP generator takes the options above, except `--payload`, and two more:

- `--pipeline=N` writes N requests at once on each connection, which is
  [pipelining](../reference/glossary.md#http). The default is 1, no pipelining.
- `--path` changes the request target.

The output adds a measure, `bad responses`: connections closed because a response was not a `200`, or had no
`Content-Length`.

One server process saturates before the generator does. Raise `--rate` until the throughput stops following it. Then
compare commits below that point.

## Compare with a base

`--compare` checks a Git reference out in `.hecate/bench-base`. It runs the same scenario files against that tree and
against your working tree, alternately (A/B/A/B), on the same host:

```sh
lua tools/run.lua bench tcp-echo --compare=origin/main --rounds=7
```

The comparison needs at least 5 rounds. The task exits with status 1 when a difference is significant (Mann-Whitney U
test, p < 0.01) **and** larger than 10 % on throughput or on p99 latency. Anything smaller is noise.

The base tree uses the native modules built in your working tree: it builds none of its own. So a change to native
code (`json`, `http`) is not compared. Measure it by hand, building each tree in turn.

## Pin the processes

On a machine with several cores, give the server and the generator disjoint cores. Pinning uses `taskset`, so it is
available on Linux only:

```sh
lua benchmarks/run.lua tcp-echo --server-pin=2 --load-pin=3
```

## Publishable figures

Numbers from a shared or virtual machine are good for comparing two commits, not for quoting. For absolute figures,
follow the procedure for a quiet host in
[`benchmarks/README.md`](https://github.com/hecate-framework/hecate/blob/main/benchmarks/README.md).

Pull requests labelled `performance` run the comparison in CI (`benchmarks.yml`).
