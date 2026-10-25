---
description: Run the TCP echo benchmark, read its latency and throughput figures, and compare your working tree with a Git reference.
hecate: "0.x"
lua: "5.5"
order: 7
---

# Measure performance

This guide shows how to run the network benchmark of the repository and how to compare a change
with its base. It is written for hecate 0.x and Lua 5.5, and runs on Linux and macOS.

The `tcp-echo` scenario starts an echo server built on `hecate.reactor` and `hecate.net`, then
drives it with a load generator written in Lua. The generator is *open loop*: each connection is
due to send one request per interval, and the latency of a request is measured from the instant
it was due, not from the instant it was sent. A slow server therefore cannot hide its queueing
(coordinated omission).

## Run the scenario

Raise the limit of open files above the number of connections, then run it:

```sh
ulimit -n 20000
lua tools/run.lua bench tcp-echo --rounds=5 --connections=10000 --rate=5000 --duration=10
```

The task prints the median, minimum and maximum of every measure over the rounds, and the ratio
between the largest and the smallest. Add `--json` for a machine-readable report.

| Measure | Unit | Meaning |
|---|---|---|
| `throughput` | requests/s | completed requests per second after the warm-up |
| `errors` | connections | connections that failed to open or broke |
| `latency p50`, `p90`, `p99`, `p99.9`, `max` | µs | latency from the due time |

A throughput below `--rate` means the server, or the generator, is saturated. Options of the load
generator are `--connections`, `--rate` (total requests per second), `--duration` and `--warmup`
(seconds), and `--payload` (bytes).

## Compare with a base

`--compare` checks a Git reference out in `.hecate/bench-base` and runs the same scenario files
against that tree and against your working tree, alternately (A/B/A/B), on the same host:

```sh
lua tools/run.lua bench tcp-echo --compare=origin/main --rounds=7
```

The task exits with status 1 when a difference is significant (Mann-Whitney U test, p < 0.01)
**and** larger than 10 % on throughput or p99 latency. Anything smaller is noise.

## Pin the processes

On a machine with several cores, give the server and the generator disjoint cores:

```sh
lua benchmarks/run.lua tcp-echo --server-pin=2 --load-pin=3
```

## Publishable figures

Numbers from a shared or virtual machine are good for comparing two commits, not for quoting. For
absolute figures, follow the procedure for a quiet host in
[`benchmarks/README.md`](https://github.com/hecate-framework/hecate/blob/main/benchmarks/README.md).
Pull requests labelled `performance` run the comparison in CI (`benchmarks.yml`).
