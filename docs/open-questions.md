# Open questions

Each entry is either a **decision** awaiting the project owner, a **research** task, or a
**spike → owner decision**: a spike report (`docs/spikes/`) with a recommendation, on
which the owner decides.
When resolved, record the outcome (ADR or specification update) and move the entry to
"Resolved" with a link.

| ID | Type | Question | Blocks |
|---|---|---|---|
| OQ-3 | research | LuaLS and StyLua support for Lua 5.5 syntax. Fallback if unsupported (ban the construct temporarily, patch upstream)? | Phase 0 tooling |
| OQ-4 | spike → owner decision | TLS: bind OpenSSL 3 directly (own binding) or adopt an existing binding (luaossl, lua-openssl) if it supports 5.5? Is mbedTLS an option for static builds? | `net` |
| OQ-5 | spike → owner decision | JSON codec: own C codec, binding to yyjson (MIT), or lua-cjson? Criteria: speed, correctness (RFC 8259), integer/float fidelity, streaming. | `json` |
| OQ-6 | spike → owner decision | HTTP/1.1 parser: bind llhttp (MIT) or write a parser in Lua? Default assumption: llhttp. Spike report: [docs/spikes/OQ-6-http-parser.md](spikes/OQ-6-http-parser.md) (recommends llhttp; awaiting owner decision). | `http` |
| OQ-7 | decision | Publishing Lua 5.4 artefacts: same rock names with a lowered build, or suffixed rocks (`hecate-core-lua54`)? Depends on how LuaRocks selects versions by `lua` dependency. | Phase 6 |
| OQ-8 | research | Multi-process serving on Windows and macOS: share the listening socket via libuv IPC handle passing from a primary process; validate load distribution. `SO_REUSEPORT` on Linux. | `kernel` |
| OQ-11 | spike → owner decision | Documentation tooling (ADR 0012). Owner preference: `hecate.doc` generates the whole site with an MDN-like presentation similar to Lua Web Docs (luadocs.com). The spike compares this with adapting an existing generator (VitePress or Starlight with a custom theme, LDoc templates, the Next.js + MDX stack of Lua Web Docs), estimates the effort of the `hecate.doc` route, tests building Lua 5.5 to WebAssembly for runnable examples of pure-Lua packages, Licence check done: Lua Web Docs uses the Tailwind UI licence, so its theme cannot be embedded in `hecate.doc` nor redistributed (ADR 0012, "Licence finding"); theme strategy decided by the owner: an original Hecate theme everywhere (ADR 0012). Remaining: generator route and visual identity, on rendered samples. Deliver the same sample pages rendered by each candidate. | website, `doc` |
| OQ-13 | research | Standalone CLI executable: embed Lua 5.5 + CLI modules + native modules into one binary per platform (e.g. luastatic-like approach); code-signing on macOS and Windows. | `cli` |
| OQ-17 | research | Split tool for mirrors: `splitsh-lite` (used by Symfony), `git subtree split`, or `git filter-repo`. Criteria: determinism, speed on large histories, Windows irrelevant (CI only), maintenance status. | `split.yml` |
| OQ-18 | spike → owner decision | ORM pattern (ADR 0011): prototype the same small domain (two entities, one association, a transaction) with Data Mapper + Unit of Work and with Active Record, in Lua 5.5 on PostgreSQL. Criteria: readability of user code, testability, performance (allocations, queries issued), fit with the object model and transparent concurrency. | `orm` |

## Resolved

| ID | Outcome |
|---|---|
| OQ-1 | luv is used unmodified, in system-Lua mode (1.53.0-0 or later): it builds and passes its full test suite on Lua 5.5.1 on Linux, macOS and Windows, with no fork and no dedicated binding. Report: [docs/spikes/OQ-1.md](spikes/OQ-1.md) (2026-10-11). |
| OQ-2 | LuaRocks 3.13+ with project-local trees is the dependency engine of `hecate.cli` on Lua 5.5 (verified on Linux, macOS and Windows). `hecate.lock` is a separate Hecate-owned file that keeps `luarocks.lock` as its exact-version source; the `luarocks.lock` format is not changed. The CLI applies the wrapper rules of [cli-and-packaging.md](architecture/cli-and-packaging.md#luarocks-integration). Report: [docs/spikes/OQ-2.md](spikes/OQ-2.md) (2026-10-11). |
| OQ-10 (part) | GitHub organisation `hecate-framework`; provisional website domain `hecate.theandre.dev`; contact `theandre.bourry@ik.me` (2026-10-11). |
| OQ-10 | luarocks.org: a dedicated account `hecate-framework` publishes all rocks (to be created by the owner; API key stored as `LUAROCKS_API_KEY`); the owner's personal account is kept as a backup maintainer if co-maintainers are supported. Rock-name availability is checked when the account is created (2026-10-11). |
| — | Documentation theme: original Hecate theme for the website and user projects; no reuse of the Tailwind UI-licensed Lua Web Docs theme (ADR 0012, 2026-10-11). |
| OQ-16 | `.github/CODEOWNERS`: `@RedNeath` owns everything (2026-10-11). |
| OQ-12 | Copyright holder: Théandre Bourry (`LICENSE`, 2026-10-11). |
| ADRs | 0006, 0007 (complete model, traits included), 0008 (own runner), 0009, 0010, 0014 (with performance condition), 0015 accepted by the owner (2026-10-11). |
| OQ-14 | Benchmarks on GitHub-hosted runners, relative A/B comparisons only, significance test + 10 % threshold ([benchmarks/README.md](../benchmarks/README.md), 2026-10-11). |
| OQ-15 | `@claude` restricted to organisation owners, members and collaborators (`claude.yml`); the Claude GitHub App and `ANTHROPIC_API_KEY` remain to be installed (2026-10-11). |
| OQ-9 | Raise error objects, `nil` for expected absence: [ADR 0018](adr/0018-error-signalling.md) (2026-10-11). |
| — | Native libraries (OQ-4, OQ-5, OQ-6) are decided by the owner on the basis of spike reports, not by agents (2026-10-11). |
