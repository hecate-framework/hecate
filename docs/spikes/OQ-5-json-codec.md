# Spike OQ-5: JSON codec

Status: **partial, decode side only (Linux only)**. Recommendation submitted to the
owner; the decision is theirs.

## Method

- yyjson 0.13.0 (MIT) with a throwaway C decoding binding (about 40 lines) that maps JSON
  integers to Lua integers, other numbers to floats, `null` to a light userdata `NULL`.
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
| depth 1000 array | accepted (depth limit 1000 by default) | accepted, **no depth limit**: the binding must add one (recursion) |

Encoding with lua-cjson: `1.0` encodes as `1`, and the decoded `[]` and `{}` both
re-encode as `{}`, so the explicit array/object markers required by the json README are not
provided and would need a wrapper.

Decode throughput, median of 11 runs of 1 000 decodes (min to max in brackets):

| Decode throughput | MB/s |
|---|---|
| lua-cjson | 57.6 (56.6 to 57.8) |
| yyjson binding | 117.0 (114.4 to 119.7) |

lua-cjson encode: 108 MB/s.

- lua-cjson fails two stated criteria outright: integer/float fidelity (everything is a
  float, integers above 2^53 are corrupted) and RFC 8259 strictness (NaN, leading zeros,
  invalid UTF-8). Fixing this means patching a library with a slow release cadence.
- yyjson meets fidelity and strictness. The decode speed gain (2 times) is moderate
  because building Lua tables dominates; yyjson alone would be several times faster.
- yyjson's mutable-document API is not designed around Lua tables; encoding would walk
  the Lua value directly into a buffer (own code), so yyjson buys the decoder, while the
  encoder remains ours either way.

## Recommendation

Do not adopt lua-cjson. Choose between (a) yyjson for decoding plus an own encoder, and
(b) an own C codec for both. On the evidence here, (a) is the cheaper route to a correct
decoder; (b) removes a third-party dependency but must reproduce yyjson's strictness and
speed. A follow-up spike item, if the owner wants (b), would be to write the decoder and
compare it on this corpus. Either way, `hecate.json` needs a depth limit, an explicit
`null` marker (light userdata or a dedicated sentinel) and array/object markers.

## Remaining risks

- yyjson maintenance and API stability (0.x version number); vendoring policy.
- Streaming (a README requirement) is not covered by any of the candidates here.
- Windows and macOS builds unverified.
