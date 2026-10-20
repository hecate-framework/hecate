# Benchmarks

Performance is a product requirement (vision.md). Benchmarks run in CI
(`benchmarks.yml`) and their history is published on the website.

## Scenarios

| Scenario | Measures | Phase |
|---|---|---|
| `tcp-echo` | reactor + net overhead, 10 000 concurrent connections | 1 |
| `plaintext` | HTTP/1.1 server, keep-alive, pipelining | 2 |
| `json` | serialisation + routing + kernel | 2 |
| `validation` | coercion and validation of path, query and content | 2 |
| `routing` | route tables of 10 / 100 / 1 000 routes | 2 |
| `db-single`, `db-multiple`, `db-updates` | PostgreSQL driver + pool + ORM (TechEmpower-like) | 4 |
| micro | per package: dispatch cost (`core`), JSON codec, router match, schema validation | 1→ |

## Method

- Load generator: `wrk2` or `oha` with constant arrival rate (coordinated-omission safe).
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

## Planned layout

`benchmarks/scenarios/<name>/` (application + load profile), `benchmarks/run.lua`,
`benchmarks/results/` (git-ignored; history stored as CI artefacts and on the website).

## Running on your own hardware

Goal: absolute numbers that mean something, together with a description of the machine that
produced them. The `bench` task browses and runs every benchmark file of the repository
(`packages/<package>/benchmarks/<name>.lua`) on a Linux host; the comparison with a baseline and the
network scenarios come with the Phase 1 harness item.

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

### Windows with QEMU

QEMU on a Linux host measures a **virtual machine**, not Windows on hardware: the numbers are
valid for comparing two commits on the same VM, never as absolute figures. To make them as
steady as possible: use KVM (`-accel kvm -cpu host`), give the guest fixed memory
(`-m 8G`, no ballooning) and a few cores pinned on the host (`taskset` on the QEMU process, or
`-smp 4` with `chrt`/`taskset` per vCPU thread), disk and network on `virtio` (install the virtio
drivers in the guest), and perform the host steps 3 to 6 above on the **host**. In the guest:
High performance power plan (`powercfg /setactive SCHEME_MIN`), no Windows Update or Defender
scan during the run (`Set-MpPreference -DisableRealtimeMonitoring $true` for the duration only), then
the same procedure. Absolute Windows figures need a physical machine (a spare PC booted on Windows,
or a Windows-to-go disk): everything above then applies unchanged.

Describe the Windows host from PowerShell, since `host-report.sh` needs a POSIX shell (Git Bash
runs it, with fewer sections): `Get-CimInstance Win32_Processor | Select Name,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed`,
`Get-CimInstance Win32_ComputerSystem | Select TotalPhysicalMemory,HypervisorPresent`,
`(Get-CimInstance Win32_OperatingSystem).Caption`, `powercfg /getactivescheme`, and the same
noise measurement:
`lua -e "..."` copied from the end of `host-report.sh`, or `sh benchmarks/host-report.sh` in Git Bash.

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
