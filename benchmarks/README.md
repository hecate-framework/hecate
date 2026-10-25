# Benchmarks

Performance is a product requirement (vision.md). Benchmarks run in CI
(`benchmarks.yml`) and their history is published on the website.

## Scenarios

| Scenario | Measures | Phase |
|---|---|---|
| `tcp-echo` | reactor + net overhead, 10 000 concurrent connections | 1 |
| `accept-spread` | multi-process serving ([ADR 0023](../docs/adr/0023-multi-process-serving.md)): connections per second and spread over the workers, per listening strategy | 1 |
| `plaintext` | HTTP/1.1 server, keep-alive, pipelining | 2 |
| `json` | serialisation + routing + kernel | 2 |
| `validation` | coercion and validation of path, query and content | 2 |
| `routing` | route tables of 10 / 100 / 1 000 routes | 2 |
| `db-single`, `db-multiple`, `db-updates` | PostgreSQL driver + pool + ORM (TechEmpower-like) | 4 |
| micro | per package: dispatch cost (`core`), JSON codec, router match, schema validation | 1→ |

## Method

- Load generator: constant arrival rate, latency from the due time (coordinated-omission safe): the Lua generator of the repository for `tcp-echo`; `wrk2` or `oha` for the HTTP scenarios.
- Report throughput, p50/p90/p99/p99.9 latency, memory, allocations per request.
- Same hardware for comparisons; 3 runs minimum; variance reported.
- Comparison targets (informative, separate job): FastAPI (uvicorn), Node.js (Fastify),
  Go (net/http), OpenResty.
- **Runners (OQ-14, resolved): GitHub-hosted runners, relative comparisons only.** The
  same job builds the base (`main`) and the head of the pull request and runs them
  alternately on the same runner (A/B/A/B, at least 5 rounds per scenario). A
  regression is reported only when the difference is statistically significant
  (Mann-Whitney U test, p < 0.01) **and** above 10 % on throughput or p99 latency.
- Absolute numbers from hosted runners are published as indicative only; comparisons
  with other frameworks are run manually on dedicated hardware before major releases.
- **Absolute numbers come from the owner's own hardware** (owner decision, 2026-10-20):
  hosted runners are noisy and heterogeneous, so the figures that are quoted or published are
  measured by hand on a dedicated machine, following [Running on your own hardware](#running-on-your-own-hardware).
  The hosted runners keep the relative A/B comparison above.

## Layout

- `benchmarks/scenarios/<name>/`: a network scenario, made of `server.lua` (starts the application under
  test, prints `listening <port>`) and `load.lua` (drives it and prints `label value unit` lines).
- `benchmarks/run.lua`: runs a scenario for several rounds and prints the median and spread of each measure.
- `benchmarks/compare.lua`: the A/B comparison of a base tree and a head tree (below).
- `benchmarks/lib/`: `runner.lua` (one round) and `stats.lua` (percentiles, median, Mann-Whitney U).
- `benchmarks/results/` (git-ignored; history stored as CI artefacts and on the website).

The load generator is written in Lua on the reactor of the repository, so that no third-party tool is needed.
It is open loop: each connection sends one request per interval, and the latency of a request is measured from
the instant it was due, not from the instant it was sent, so a slow server cannot hide its queueing
(coordinated omission). `wrk2` or `oha` stay an option for the later HTTP scenarios, run by hand on dedicated hardware.

```sh
lua tools/run.lua bench tcp-echo --rounds=5 --connections=10000 --rate=5000 --duration=10
lua tools/run.lua bench tcp-echo --compare=origin/main        # A/B/A/B against a git reference
lua benchmarks/run.lua tcp-echo --server-pin=2 --load-pin=3   # directly, with pinned processes
```

Options of the load generator: `--connections`, `--rate` (total requests per second), `--duration` and
`--warmup` (seconds), `--payload` (bytes). Raise `ulimit -n` above the number of connections first. Latency
is reported in microseconds (p50, p90, p99, p99.9, max), throughput in requests per second, `errors` in
connections that failed. A throughput below `--rate` means the server (or the generator) is saturated.
`--compare` checks the reference out in `.hecate/bench-base` and runs the same scenario files against that tree
and the working tree, alternately, on this host; it exits with status 1 on a significant regression.

## Running on your own hardware

Goal: absolute numbers that mean something, together with a description of the machine that
produced them. The `bench` task browses and runs every benchmark file of the repository
(`packages/<package>/benchmarks/<name>.lua`) on a Linux host; the network scenarios and the comparison with
a baseline are run as shown in [Layout](#layout).

```sh
lua tools/run.lua bench --list                      # what exists
lua tools/run.lua bench                             # on a terminal: a menu (1,3-4 / a = all / q)
lua tools/run.lua bench all --runs=5 --pin=2,3      # everything, 5 rounds, on CPUs 2 and 3
lua tools/run.lua bench json core/dispatch --yes    # a package, or one benchmark; --yes: measure
                                                    # even if the host checks warn
```

Each round runs every selected benchmark once (so that drift is spread, not concentrated on one
benchmark). The task warns before starting when the host is not quiet (governor, turbo, SMT, swap,
load, graphical session; `--strict` makes that an error), writes `host-before.md` and
`host-after.md` (`host-report.sh`), the raw output of every run, and `summary.md` with the minimum,
median, maximum and max/min spread of every measure, in `benchmarks/results/<host>-<date>/`.
A benchmark is a Lua file, run from the repository root, whose first line is a comment describing it
and which prints measurement lines of the form `<label> <value> <unit>` (for example
`decode records native 312.4 MB/s`); other lines are kept in the raw output only. The steps below
(quiet machine, pinning, several runs) are what `bench` expects you to have done.

### Ubuntu 24.04 (reference platform)

1. **Install the toolchain** once: `sh tools/bootstrap.sh` (Lua 5.5, `luarocks`), a C compiler, `cmake` and `cargo` and, for the network scenarios, a load generator (`wrk2` or `oha`)
   and a **second machine** if you have one (see "Load generator" below).
2. **Build** a clean checkout of the commit to measure (record it, the host report does):
   `git clone`, `git checkout <commit>`, `lua tools/run.lua build-native json`.
3. **Leave the graphical session.** Switch to a text console with `Ctrl+Alt+F3` (log in there), or
   better, stop the desktop for the run: `sudo systemctl isolate multi-user.target` (back with
   `sudo systemctl isolate graphical.target`). Better still, boot once with `systemd.unit=multi-user.target`
   on the kernel command line. Run the benchmark inside `tmux` so that a closed SSH session does
   not kill it.
4. **Quiet the machine.** On a desktop or laptop: plug in the power supply, close the browser and
   every sync client, `sudo systemctl stop unattended-upgrades apt-daily.timer apt-daily-upgrade.timer`,
   disable swap if you have any (`sudo swapoff -a`), and let the machine cool down for a few
   minutes after the build.
5. **Fix the clock speed.** Frequency scaling is the largest source of noise.
   - Governor: `sudo cpupower frequency-set -g performance` (package `linux-tools-generic`), or
     `echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor`.
   - Turbo: for the most repeatable result turn it off
     (`echo 1 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo`, or
     `echo 0 | sudo tee /sys/devices/system/cpu/cpufreq/boost` on AMD); leave it on to measure what
     users get, and then say so in the notes. Do not mix both in one comparison.
   - SMT: `echo off | sudo tee /sys/devices/system/cpu/smt/control` removes the noise of a busy
     sibling thread.
6. **Pin the process** to cores that nothing else uses: `taskset -c 2,3 lua ...` (isolating them
   with the `isolcpus=2,3` kernel parameter is optional). Pin the load generator to other cores.
7. **Describe the host**, before and after the run (the two reports show drift, such as
   temperature or a background job that woke up):
   `mkdir -p benchmarks/results/<host>-<date>` then
   `sh benchmarks/host-report.sh > benchmarks/results/<host>-<date>/host-before.md`.
   The report holds the operating system, virtualisation, CPU model, cores, caches, governor,
   turbo and SMT state, memory, storage, load, temperatures, toolchain versions, and a **noise
   measurement**: a fixed Lua workload repeated 15 times. A spread (max/min) above 1.05 means the
   machine is not quiet enough; find the cause before measuring (`top`, `sensors`, the governor).
8. **Run** at least 3 times, alternating base and head if you compare two commits (A/B/A/B, at least
   5 rounds), and keep every run, not the best one:
   `taskset -c 2,3 lua <benchmark> | tee benchmarks/results/<host>-<date>/run-<n>.txt`.
9. **Restore** the machine (`isolate graphical.target`, governor, turbo, SMT).
10. **Report** the median and the variance of the runs next to the host report. Throughput and
    latency (p50, p90, p99, p99.9) for network scenarios, memory and allocations for the others.
    Results never go into the repository (`benchmarks/results/` is git-ignored); a summary with
    the host description goes to the issue, the pull request or the release notes that quote it.

#### Load generator

For `tcp-echo`, `plaintext` and `json`, the load generator competes with the server for CPU and
memory bandwidth. Best: a second machine on a wired network, one switch away, with the same quiet
procedure. Otherwise run both on one machine, on disjoint pinned cores, over the loopback
interface, and say so: the numbers then measure the server under a handicap and are good for
comparing commits, not for comparing frameworks.

### Windows

Windows is not a benchmark target (owner decision, 2026-10-25): Linux is the only production target and
Windows is a development platform (see [the vision](../docs/vision.md)). The network scenarios need a POSIX
shell, `taskset` and `kill`, and no work should be started to port them. The micro-benchmarks of the packages
run wherever Lua runs, but their numbers are not published for Windows.

### macOS

macOS runs legally only on Apple hardware, and QEMU on other hardware is not a supported way to
measure it: do not publish numbers from it. Run on a real Mac: plug in, close applications,
`sudo pmset -a sleep 0 disablesleep 1` for the run, `caffeinate -dims` around the command, Low
Power Mode off, Spotlight indexing finished (`mdutil -s /`), and let the machine cool down.
Apple Silicon has no frequency governor to set; compare runs of the same cooled-down machine only.
`sh benchmarks/host-report.sh` works there (it uses `sysctl` and `sw_vers`).

### What to compare

- Same machine, same state, same commit built the same way, in the same session.
- Never compare a run with turbo on to one with turbo off, nor a quiet run to a noisy one (read
  the noise line of the two host reports first).
- A difference smaller than the spread of the noise measurement is not a result.

### `accept-spread`

A primary starts N worker processes (`reactor.spawn` with a message pipe) that echo what they receive. The load
generator opens short connections at a constant rate and, at the end, asks the server's control port how many
connections each worker accepted. The **spread** is the largest count over the smallest (1.00 is perfect, ADR 0023).

```sh
lua benchmarks/run.lua accept-spread --server-args="round_robin 4" --rate=2000 --duration=10
lua benchmarks/run.lua accept-spread --server-args="reuseport 4"
```

`--server-args` is `<strategy> <workers>` (default `round_robin 4`). `round_robin`: the primary accepts and passes
each connection to the next worker. `reuseport`: each worker binds with `SO_REUSEPORT`; it is reported as skipped
while `reactor.supports_reuseport()` is false (luv without TCP `reuseport`, OQ-43). The load options are `--rate`
(connections per second), `--duration` and `--payload`. The baseline per strategy is measured by the owner on
dedicated hardware.
