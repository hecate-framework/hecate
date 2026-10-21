#!/bin/sh
# Describes the machine a benchmark run is executed on, as Markdown on standard output, and
# measures its noise with a fixed Lua workload. Usage (from the repository root):
#   sh benchmarks/host-report.sh > benchmarks/results/<host>-<date>/host.md
# Linux and macOS only; the Windows equivalent is in benchmarks/README.md.
LUA=${LUA:-lua}
have() { command -v "$1" >/dev/null 2>&1; }
section() { printf '\n## %s\n\n' "$1"; }
block() { printf '```text\n'; cat; printf '```\n'; }

printf '# Host report\n\n'
printf -- '- date (UTC): %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf -- '- host name: %s\n' "$(hostname 2>/dev/null)"
if have git; then
  printf -- '- commit: %s%s\n' "$(git rev-parse --short HEAD 2>/dev/null)" \
    "$(git diff --quiet 2>/dev/null || printf ' (dirty)')"
fi

section "Operating system"
{ uname -a; [ -r /etc/os-release ] && . /etc/os-release && printf '%s\n' "$PRETTY_NAME"
  have sw_vers && sw_vers; } | block

section "Virtualisation"
{ if have systemd-detect-virt; then systemd-detect-virt || true
  elif [ "$(uname)" = Darwin ]; then sysctl -n kern.hv_vmm_present 2>/dev/null; fi; } | block

section "Processor"
if [ "$(uname)" = Darwin ]; then
  { sysctl -n machdep.cpu.brand_string; sysctl hw.physicalcpu hw.logicalcpu hw.cpufrequency hw.l2cachesize \
      hw.l3cachesize 2>/dev/null; } | block
elif have lscpu; then
  lscpu | grep -E 'Model name|Architecture|^CPU\(s\)|Thread|Core|Socket|MHz|L1d|L2|L3|Virtualization|Hypervisor|Flags' \
    | sed 's/Flags:.*/Flags: (omitted)/' | block
fi
{ for f in /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor /sys/devices/system/cpu/intel_pstate/no_turbo \
    /sys/devices/system/cpu/cpufreq/boost /sys/devices/system/cpu/smt/active; do
    [ -r "$f" ] && printf '%s = %s\n' "$f" "$(cat "$f")"
  done; } | block

section "Memory and swap"
if [ -r /proc/meminfo ]; then
  { grep -E 'MemTotal|MemAvailable|SwapTotal|SwapFree' /proc/meminfo
    [ -r /sys/kernel/mm/transparent_hugepage/enabled ] && printf 'THP: %s\n' "$(cat /sys/kernel/mm/transparent_hugepage/enabled)"
  } | block
elif [ "$(uname)" = Darwin ]; then sysctl hw.memsize vm.swapusage | block; fi

section "Storage and network"
{ have lsblk && lsblk -d -o NAME,MODEL,SIZE,ROTA,TYPE 2>/dev/null
  have ip && ip -br link 2>/dev/null; } | block

section "Load before the run"
{ uptime; have ps && ps -eo pcpu,comm --sort=-pcpu 2>/dev/null | head -6; } | block

section "Temperatures"
{ have sensors && sensors 2>/dev/null | head -20; } | block

section "Toolchain"
{ "$LUA" -v 2>&1; have cc && cc --version | head -1; have cargo && cargo --version
  have luarocks && luarocks --version | head -1; have wrk && wrk --version 2>&1 | head -1
  have oha && oha --version; } | block

section "Noise of this machine"
printf 'A fixed Lua workload (under 0.1 s of CPU time), repeated 15 times. A quiet machine shows a\n'
printf 'spread (max/min) close to 1.00; above 1.05, find what is disturbing it before benchmarking.\n\n'
"$LUA" -e '
local function work()
  local t = os.clock()
  local s = 0
  for i = 1, 4000000 do s = s + (i % 7) * 3 end
  local x = {}
  for i = 1, 100000 do x[i] = tostring(i) end
  return os.clock() - t, s
end
work()
local runs = {}
for i = 1, 15 do runs[i] = (work()) end
table.sort(runs)
local sum = 0
for _, r in ipairs(runs) do sum = sum + r end
local mean = sum / #runs
local var = 0
for _, r in ipairs(runs) do var = var + (r - mean) ^ 2 end
print(string.format("min %.4f s, median %.4f s, max %.4f s, spread max/min %.3f, coefficient of variation %.2f %%",
  runs[1], runs[8], runs[#runs], runs[#runs] / runs[1], 100 * math.sqrt(var / #runs) / mean))
' | block
