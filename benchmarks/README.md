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

## Planned layout

`benchmarks/scenarios/<name>/` (application + load profile), `benchmarks/run.lua`,
`benchmarks/results/` (git-ignored; history stored as CI artefacts and on the website).
