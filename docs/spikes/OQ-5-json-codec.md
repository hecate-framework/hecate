# Spike OQ-5: JSON codec

Status: **partial, decode side only (Linux only)**. Recommendation submitted to the
owner; the decision is theirs.

## Method

- yyjson 0.13.0 (MIT) with a throwaway C decoding binding (about 40 lines) that maps JSON
  integers to Lua integers, other numbers to floats, `null` to a light userdata `NULL`.
- lunajson 1.2 line (`grafi-tt/lunajson`, MIT, last commit 2026-02-21), a pure-Lua codec,
  run unmodified on Lua 5.5.1: the only candidate with no C code.
- lua-cjson, `mpx/lua-cjson` master (MIT; last commit April 2024), built unmodified against
  Lua 5.5.1 with GCC `-O2`. `openresty/lua-cjson` was cloned but not evaluated.
- 20 decoding cases (RFC 8259 conformance, number fidelity, malformed input) and a decode
  benchmark on a 17.7 kB document of 200 objects, 11 runs of 1 000 iterations, median reported; encode benchmark for
  lua-cjson only.

Code in `spikes/OQ-5/` (git-ignored). **Not done:** an own C codec was not written (it is
the largest of the three options and no basis for comparison exists yet); yyjson encoding
(needs a Lua-table walk and the array/object marker rules of the json README); macOS and
Windows builds; streaming.

## Findings

| Case | lua-cjson | yyjson binding |
|---|---|---|
| `42` | **float 42.0** (no integer type) | integer 42 |
| `9007199254740993` (2^53+1) | float, **rounded** to ...992 | integer, exact |
| `9223372036854775807` | float, rounded | integer, exact |
| `9223372036854775808` | float | float |
| `1e400` | **inf** accepted | rejected |
| `NaN`, `01` | `NaN` accepted, `01` read as 1 | rejected |
| `-0` | float -0.0 | integer 0 (sign lost) |
| lone surrogate, trailing comma, trailing garbage, empty input | rejected | rejected |
| raw invalid UTF-8 inside a string | **accepted** | rejected |
| depth 1000 array | accepted (depth limit 1000 by default) | accepted |
| depth 5000 array | rejected (limit 1000) | **my binding crashes** (`corrupted double-linked list`, process abort): its recursion has no depth limit; yyjson itself has none, so the binding must impose one |

lunajson (pure Lua) on the same cases: integers are exact (`42` and 2^53+1 and int64 max
all stay Lua integers, like yyjson); `01`, `NaN`, trailing comma, lone surrogate, trailing
garbage and empty input are rejected; `1e400` gives **inf** and raw invalid UTF-8 inside a
string is **accepted** (same two gaps as lua-cjson); `-0` gives float -0.0; nesting over
1000 levels is rejected with an error. It is the most faithful of the three to integer
fidelity without any C code, but it is the slowest by a wide margin.

Encoding with lua-cjson: `1.0` encodes as `1`, and the decoded `[]` and `{}` both
re-encode as `{}`, so the explicit array/object markers required by the json README are not
provided and would need a wrapper.

Decode throughput, median of 11 runs of 1 000 decodes (min to max in brackets):

| Decode throughput | MB/s |
|---|---|
| lunajson (pure Lua) | 12.7 (12.3 to 13.0) |
| lua-cjson | 58.3 (57.4 to 59.9) |
| yyjson binding | 125.2 (122.0 to 129.6) |

(Second series of 11 runs, taken when lunajson was added; the first series gave 57.6 and
117.0 MB/s for lua-cjson and yyjson, so runs on this VM agree within about 7 %.)

lua-cjson encode: 108 MB/s.

- lunajson is about 10 times slower than yyjson and 4.6 times slower than lua-cjson. For a
  JSON API framework where decoding sits on the request path, that is probably too slow
  for the default codec, but it is a credible fallback for platforms without a C compiler
  and a useful correctness reference.
- lua-cjson fails two stated criteria outright: integer/float fidelity (everything is a
  float, integers above 2^53 are corrupted) and RFC 8259 strictness (NaN, leading zeros,
  invalid UTF-8). Fixing this means patching a library with a slow release cadence.
- yyjson meets fidelity and strictness. The decode speed gain (2 times) is moderate
  because building Lua tables dominates; yyjson alone would be several times faster.
- yyjson's mutable-document API is not designed around Lua tables; encoding would walk
  the Lua value directly into a buffer (own code), so yyjson buys the decoder, while the
  encoder remains ours either way.

## Recommendation

Do not adopt lua-cjson. lunajson is correct on integers but too slow as the default codec. Choose between (a) yyjson for decoding plus an own encoder, and
(b) an own C codec for both. On the evidence here, (a) is the cheaper route to a correct
decoder; (b) removes a third-party dependency but must reproduce yyjson's strictness and
speed. A follow-up spike item, if the owner wants (b), would be to write the decoder and
compare it on this corpus. Either way, `hecate.json` needs a depth limit, an explicit
`null` marker (light userdata or a dedicated sentinel) and array/object markers.

## Remaining risks

- yyjson maintenance and API stability (0.x version number); vendoring policy.
- Streaming (a README requirement) is not covered by any of the candidates here.
- Windows and macOS builds unverified.

## Addendum: encoder candidates (owner decision: yyjson decodes, a Lua library encodes)

Pure-Lua encoders on a 15 kB document, median of 11 runs of 200 encodes (lua-cjson, C,
for reference):

| Encoder | MB/s |
|---|---|
| lunajson | 14.5 |
| rxi/json.lua | 9.4 |
| dkjson | 8.8 |
| lua-cjson (C) | 98.9 |

lunajson is the fastest pure-Lua candidate tested, about 7 times slower than a C encoder.
Array/object marker behaviour differs (lunajson and cjson encode an empty table as `{}`,
rxi and dkjson as `[]`); `hecate.json` needs its own explicit markers anyway. The encoder is
the place to optimise later (own C encoder, or specialised Lua code paths for known
schemas), since `hecate.schema` knows the shape of responses in advance.

## Addendum: Rust JSON libraries through `mlua` (owner question)

Throwaway module `spikes/OQ-5/rust-json/` (mlua 0.12.2 with `lua55` and `serialize`,
serde_json 1, sonic-rs 0.5, simd-json 0.17, release build with LTO), Lua 5.5.1, Linux,
median of 11 runs (same documents as above).

Decoding goes through serde into Lua values (`lua.to_value`), so it builds a Rust value
first and then a Lua table:

| Decoder | MB/s | Notes |
|---|---|---|
| yyjson binding (direct to Lua) | 130.4 | rejects every malformed case |
| lua-cjson | 60.8 | |
| sonic-rs via serde bridge | 30.5 | |
| simd-json via serde bridge | 24.6 | accepts a lone surrogate (string of length 1) |
| serde_json via serde bridge | 23.4 | |
| lunajson | 12.7 | |

All three Rust decoders keep integers exact, reject NaN, `01`, `1e400`, trailing commas,
raw invalid UTF-8 and trailing garbage; all reject nesting at 1000 levels (serde_json's
default limit is 128) without crashing. The double conversion makes them 4 to 5 times
slower than yyjson. A decoder writing Lua values directly would be faster, but it is
code of our own.

Encoding straight from Lua tables is possible (mlua implements `Serialize` for Lua
values, and a hand-written walk is about 40 lines):

| Encoder | MB/s |
|---|---|
| lua-cjson (C, raw Lua C API) | 98.7 |
| Rust, hand-written table walk | 54.2 |
| Rust, serde bridge (serde_json) | 52.9 |
| lunajson (pure Lua) | 15.1 |

The Rust encoders are 3.5 times faster than lunajson, which is the pure-Lua encoder
chosen in ADR 0020. They stay at half the speed of lua-cjson because `mlua`'s safe API
pays per-element access costs; an `unsafe` direct use of the Lua C API in Rust would close
part of that gap but gives up the memory-safety argument. The hand-written walk was no
faster than the serde bridge, so the access cost, not the serialisation, dominates. Behaviour
differences to settle in a real implementation: floats with a zero fraction (`1.0`) come out
as `1` from the hand-written walk and `1.0` from serde_json; empty tables encode as `{}`.

Consequences for the decision: a Rust encoder would be roughly 3.5 times faster than the
Lua encoder of ADR 0020, at the price of the Rust toolchain being a build requirement,
which is the same question as for TLS (OQ-4). If the owner accepts Rust as a build-time
tool for TLS, using it for the encoder as well adds no new cost category. Decoding should
stay on yyjson.
