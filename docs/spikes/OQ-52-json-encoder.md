# Spike OQ-52: the JSON encoder, hand-written or on `serde_json`

Status: **done (Linux, Ubuntu 24.04 on a shared 4-vCPU VM; numbers are indicative, see "Reproduce")**.
Recommendation submitted to the owner; the decision is theirs.

## Question

ADR 0020 and ADR 0021 choose `serde_json` through `mlua` for the encoder of `hecate.json`, so as not to write
an encoder. The encoder of the pull request (`packages/json/native`) is hand-written and uses `mlua` only, for a
reason recorded in the branch: the codec's float text (the fewest of 15, 16, 17 digits, `1.0` stays a float)
"is not what serde's shortest-digits output produces". That reason was never tested. Is the decision to
write it by hand justified by what `serde_json` can and cannot do?

## Method

Three candidates, all against the same contract (`bind`, `encode(value, options) -> text | nil`) and the same
shared suites, differential tests and fuzz test of `packages/json/tests`:

- **A, hand-written** (the pull request): 368 lines of Rust, `mlua` only.
- **B, `serde_json`** (`docs/spikes/OQ-52/serde-encoder`, 279 lines): a `Serialize` implementation over the Lua
  value (the walk: markers, array or object, holes, key order, depth and size limits) driven by
  `serde_json::Serializer` with a custom `Formatter` (`write_f64` for the codec's float text; `CompactFormatter`
  or `PrettyFormatter` for the rest). `serde_json` writes the string escapes, the integers, the punctuation and
  the indentation. The run builds `serde`, `serde_json`, `itoa` and `zmij` more than A (35 crates in
  `Cargo.lock` against 31).
- **C, `mlua`'s own serde bridge** (`docs/spikes/OQ-52/mlua-bridge`, feature `serialize`):
  `serde_json::to_string(&value)` with no code of ours, with the default options and with the closest tuning
  (`deny_unsupported_types`, `deny_recursive_tables`, `detect_mixed_tables`).

Plus a measurement of the float text: does the codec's format (`%.15g` to `%.17g`) differ from `serde_json`'s
own (shortest round trip) in the digits written?

Versions: Rust 1.97.0, `mlua` 0.12.2, `serde_json` 1.0.154, Lua 5.5.1.

## Findings

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
an error). The walk has to be ours in every design, which is what B and A both contain.

### B works, and the reason given for A does not hold

- B passes the whole `json` test suite, including the differential tests against the reference encoder
  (corpus, 40 000 random floats, random values, `canonical`, indentation, depth and size limits) and the fuzz
  test (also run for 40 s). The tests were shown to run against B (a corrupt module in its place fails them).
- `serde_json` lets a `Formatter` replace `write_f64`, so the codec's float text is reproducible on `serde_json`:
  the argument against `serde_json` was wrong. The float function itself is the same in A and B (about 45 lines).
- What B removes from A: string escaping, integer writing, the commas, colons and brackets, indentation: about
  90 lines (368 to 279, 24 %). What stays ours is the walk, as in every design.

### The digits of the codec and of `serde_json` agree, except for rare subnormals

`docs/spikes/OQ-52/float-digits.lua`: 300 000 random IEEE doubles (uniform bit patterns) and 300 000 decimal-looking
doubles (few digits, magnitudes 1e-25 to 1e17). Digits equal everywhere except **4 subnormal numbers out of the
random set** (for example `-7.96803451801022e-310` against `-7.9680345180102e-310`: both read back as the same
double, the codec writes more digits because `%.15g` is its floor). None for the decimal-looking set. Only the layout
differs: `serde_json` writes `1e21` and `1e-7` where the codec writes `1e+21` and `1e-07`; both are valid JSON and
both decode as floats.

### Speed

`lua tools/run.lua bench json/codec --pin=2`, A and B alternating over four rounds (A, B, A, B, ...), median MB/s:

| Encode, native backend | A hand-written | B `serde_json` + codec float text | B2: `serde_json` own float text |
|---|---|---|---|
| records (objects, short strings, floats) | 27.9 | 29.6 | 45.4 |
| numbers (integers and floats) | 23.0 | 23.9 | 63.7 |
| strings (escapes, non-ASCII) | 176 | 211 | 216 |

(B2 is B with `write_f64` left to `serde_json`; not conforming to the current float text, measured only to size
the cost of that text. Three runs, no alternation.) The reference encoder (pure Lua) writes 7 MB/s on records and
numbers and 28 MB/s on strings, on the same VM.

- A and B are within the noise of a shared VM (A/B spread of 1.0 to 1.4 on the strings case): **no measurable
  speed difference between writing it by hand and using `serde_json`**. The cost is the walk of the Lua table
  and, for numbers, the float text.
- **The float text of the codec costs a factor of 2.8 on number-heavy documents** and 1.5 on records. The 53 MB/s of
  ADR 0020 was measured with `serde_json`'s own float output; with the codec's float text neither A nor B comes
  near it on numbers.

## Recommendation

1. The decision is not between hand-written and `serde_json`: both are correct and as fast. It is **the float
   text**. Keep `%.15g` to `%.17g` (stable, equal to what the reference Lua encoder can produce cheaply, and costing a
   factor 2.8 on numbers), or specify the shortest round trip (`serde_json`'s output, the same digits except in rare
   subnormals; the layout `1e21` instead of `1e+21`).
2. If the float text becomes the shortest round trip: **B2**, which is `serde_json` as the ADRs say, with no custom
   formatter, about 220 lines of ours, and the ADRs stand. The pure-Lua reference encoder and its oracle role must
   then follow (a shortest round trip in Lua is exact only with a dedicated algorithm; the 15 to 17 loop agrees with
   it except for subnormals, which the differential tests would have to tolerate or the reference would have to
   implement).
3. If the float text stays: **keep A** and amend ADR 0020 and ADR 0021 (nothing gained by B in speed, B saves about
   90 lines and costs four crates in `cargo audit` and `cargo deny`), or move to **B** if the project prefers to
   follow the ADRs and not to own an escaper and a writer. Both are defensible; this is a taste about owning
   about 90 lines against four dependencies.

Not recommended: C.

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
```
