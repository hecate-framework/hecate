# Spike OQ-52: the JSON encoder, hand-written or on `serde_json`

Status: **done (Linux, Ubuntu 24.04 on a shared 4-vCPU VM; numbers are indicative, see "Reproduce")**.
Recommendation submitted to the owner; the decision is theirs.

## Question

ADR 0020 and ADR 0021 choose `serde_json` through `mlua` for the encoder of `hecate.json`, so as not to write
an encoder. The encoder of the pull request (`packages/json/native`) is hand-written and uses `mlua` only, for a
reason recorded in the branch: the codec's float text (the fewest of 15, 16, 17 digits, `1.0` stays a float)
"is not what serde's shortest-digits output produces". That reason was never tested. Is the decision to
write it by hand justified by what `serde_json` can and cannot do?

## What was measured

- **Throughput, in MB/s (higher is faster):** the size of the JSON text in megabytes divided by the time the
  operation takes. Each figure is the median of 7 repetitions after one warm-up repetition.
- **Three generated documents of about 2 MB** (same on every machine, fixed seed), written by
  `packages/json/benchmarks/codec.lua`:
  - *records*: about 14 000 objects (integer id, name, float score, boolean, `null`, a list of two tags, a position of
    two floats), typical API data;
  - *numbers*: about 175 000 numbers, half integers and half floats, which stresses number formatting;
  - *strings*: long strings with quotes, backslashes, newlines, tabs, accents and an emoji, which stresses escaping.
- **Only encoding on the native backend** matters here (the reference backend is the pure-Lua fallback; it writes
  about 7 MB/s on records and numbers and 28 MB/s on strings on the same VM).
- A and B ran **alternately**, four rounds each (A, B, A, B, ...), pinned to one CPU, to spread the drift of a shared VM;
  the table gives the median of the four.

## The candidates

| Label | What it is |
|---|---|
| **A** | The encoder of the pull request: hand-written Rust, `mlua` only, 368 lines. It writes the JSON text itself: string escaping, integers, floats, punctuation, indentation. |
| **B** | The encoder on `serde_json` (`docs/spikes/OQ-52/serde-encoder`), 279 lines. `serde_json` writes the string escapes, the integers, the punctuation and the indentation (`CompactFormatter`, `PrettyFormatter`). Our code is the walk of the Lua value (markers, array or object, holes, key order, limits) and a custom `Formatter::write_f64` that gives the float text of the codec. Four crates more than A (`serde`, `serde_json`, `itoa`, `zmij`: 35 crates in `Cargo.lock` against 31). |
| **B2** | B with the float text left to `serde_json`. Measured only to size what the codec's float text costs; **not conforming**, see below. |
| **C** | `mlua`'s serde bridge (`docs/spikes/OQ-52/mlua-bridge`, feature `serialize`): `serde_json::to_string(&value)` with no code of ours. |

Versions: Rust 1.97.0, `mlua` 0.12.2, `serde_json` 1.0.154, Lua 5.5.1.

## Findings

### B conforms and is as fast as A

- B passes the whole `json` test suite, including the differential tests against the reference encoder (corpus,
  40 000 random floats, random values, `canonical`, indentation, depth and size limits) and the fuzz test (also run for
  40 s). The tests were shown to run against B (a corrupt module in its place fails them).
- **Three encoders exist, not two.** The *reference encoder* is the pure-Lua one (`packages/json/src/hecate/json/internal/reference.lua`):
  it is the specification in code, the test oracle and the fallback when no native module is built. A and B are two Rust
  implementations of the same contract; the tests compare each of them with the reference encoder.
- **A and B compared directly, byte for byte** (`docs/spikes/OQ-52/ab-differential.lua`): 1 700 000 random values (nesting up
  to 5 levels and chains of 30, integers including the extremes, floats from random bit patterns, decimals and
  special values, strings with controls, quotes, accents, emoji and invalid UTF-8, holes, marked and unmarked tables,
  mixed keys) with random options (indentation, `canonical`, `max_depth`, `max_size`): 1 170 000 values encoded by both,
  the same text every time; the other values declined by both (`nil`, the reference encoder then answers); no value
  encoded by only one of them. The chain encode, decode, encode again (in canonical order, since the member order of an
  unmarked table is that of `pairs`) gave the same text for every one of the 1 170 000 values.
- **Strings are escaped identically** (checked in `docs/spikes/OQ-52/float-layout.lua`): `"` `\` `\b` `\f` `\n` `\r` `\t`,
  other control characters as `\u00xx` in lower case, everything else, including DEL, accents and emoji, written as is.
- `serde_json` lets a `Formatter` replace `write_f64`, so the codec's float text is reproducible on it. The argument
  recorded in the branch against `serde_json` (its float output differs) was true only of its default output.
- What B removes from A: string escaping, integer writing, commas, colons, brackets, indentation: about 90 lines
  (368 to 279, 24 %). What stays ours is the walk, as in every design, and the float function (about 45 lines).

### Encode speed (MB/s, higher is better)

| Document | A (hand-written) | B (`serde_json`) | B2 (`serde_json`, own floats; not conforming) |
|---|---|---|---|
| records | 27.9 | 29.6 | 45.4 |
| numbers | 23.0 | 23.9 | 63.7 |
| strings | 176 | 211 | 216 |

A and B are within the noise of a shared VM (the spread between rounds reaches 1.4 on strings): **no measurable speed
difference between writing it by hand and using `serde_json`**. B2 was three runs, not alternated.

### What B2 changes (the float text only)

Strings, integers, punctuation and indentation are the same as in B. Only some floats are written differently;
all remain valid JSON and decode as floats:

| Value | Codec (A, B) | `serde_json` own (B2) |
|---|---|---|
| `1e15` | `1e+15` | `1000000000000000.0` |
| `1e-5` | `1e-05` | `0.00001` |
| `1e-7` | `1e-07` | `1e-7` |
| `5e-324` (smallest subnormal) | `4.94065645841247e-324` | `5e-324` |
| `1.0`, `0.5`, `100.0`, `0.1 + 0.2`, `1e21`, `-0.0`, `2^53` | identical | identical |

The **digits** are the same on 300 000 random doubles (uniform bit patterns) and 300 000 decimal-looking ones, except for
4 rare subnormal numbers out of the random set (`docs/spikes/OQ-52/float-digits.lua`). So the codec's float text costs
a factor 2.8 on number-heavy documents and 1.5 on records against `serde_json`'s own, for a text that differs only in
layout. The 53 MB/s of ADR 0020 was measured with `serde_json`'s own float output.

### C is not usable as it stands

The bridge knows nothing of the value model of the codec. Output of `docs/spikes/OQ-52/bridge-cases.lua`
(codec, default bridge, tuned bridge):

| Case | Codec | `mlua` default | `mlua` tuned |
|---|---|---|---|
| `json.array()` | `[]` | `{}` | `[]` |
| `json.object()` | `{}` | `{}` | `[]` |
| `{ a = json.null }` | `{"a":null}` | `{"a":{}}` | `{"a":[]}` |
| `{ 1, nil, 3 }` | `[1,null,3]` | `[1]` | `[1,null,3]` |
| mixed `{ 1, 2, a = 3 }` | error | `[1,2]` | `{"1":1,"2":2,"a":3}` |
| invalid UTF-8 string | error | `[[255]]` | `[[255]]` |
| NaN | error | `[null]` | `[null]` |
| `{ list = json.array(), map = json.object() }` | `{"map":{},"list":[]}` | `{"map":{},"list":{}}` | `{"map":[],"list":[]}` |

Markers, `null`, holes, invalid UTF-8 and NaN are wrong in one or both settings, and wrong silently (valid text, not
an error).

## Recommendation

1. **B is the better choice**: it conforms to the same standard as A, is as fast, has about 90 lines less to
   maintain and is what ADR 0020 and ADR 0021 already say (`serde_json` through `mlua`; the ADRs stand, with the
   detail that the walk and the float text are ours, as in any design). The cost is four crates in `cargo audit` and
   `cargo deny`. Not C.
2. Separate question, not blocking: the **float text**. Keeping the codec's format (`%.15g` to `%.17g`) costs a factor
   2.8 on numbers and 1.5 on records against `serde_json`'s own. Adopting `serde_json`'s own text (B2) would remove the
   custom formatter, but changes the layout of some floats (table above) and the pure-Lua reference encoder, the test
   oracle, would have to follow (a shortest round trip is exact in Lua only with a dedicated algorithm). Revisit with the
   benchmarks on dedicated hardware if number-heavy payloads matter.

## Risks and what was not done

- Numbers come from a shared 4-vCPU VM, not from dedicated hardware: use `bench` as described in
  `benchmarks/README.md` to confirm (below).
- Only Linux and Lua 5.5.1; Windows and macOS were not built for B.
- `cargo audit` and `cargo deny` were not run on B (the CI job does it for `packages/*/native`, not for this
  directory).
- Memory use and the time of the failure path (a value that A or B give up on: `nil`, then the reference encoder)
  were not measured.

## Reproduce

```sh
# B: build and put it where the harness and the benchmark look first (spikes/rocks, git-ignored)
cargo build --release --manifest-path docs/spikes/OQ-52/serde-encoder/Cargo.toml --target-dir spikes/OQ-52/target
mkdir -p spikes/rocks/lib/lua/5.5/hecate/json
cp spikes/OQ-52/target/release/libhecate_json_encoder_native.so spikes/rocks/lib/lua/5.5/hecate/json/encoder_native.so
lua tools/run.lua test json                       # the suites, differential and fuzz tests run against B
lua tools/run.lua bench json/codec --runs=5 --pin=2 --yes
rm spikes/rocks/lib/lua/5.5/hecate/json/encoder_native.so   # back to A (lua tools/run.lua build-native json)
lua tools/run.lua bench json/codec --runs=5 --pin=2 --yes
# C and the float digits
cargo build --release --manifest-path docs/spikes/OQ-52/mlua-bridge/Cargo.toml --target-dir spikes/OQ-52/target-bridge
mkdir -p spikes/OQ-52/bridge && cp spikes/OQ-52/target-bridge/release/libbridge.so spikes/OQ-52/bridge/bridge.so
lua docs/spikes/OQ-52/bridge-cases.lua
lua docs/spikes/OQ-52/float-digits.lua 300000
lua docs/spikes/OQ-52/float-layout.lua
lua docs/spikes/OQ-52/ab-differential.lua .hecate/rocks/lib/lua/5.5/hecate/json/encoder_native.so spikes/OQ-52/target/release/libhecate_json_encoder_native.so 500000 1
```
