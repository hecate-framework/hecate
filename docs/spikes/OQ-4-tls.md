# Spike OQ-4: TLS library and binding

Status: **partial (Linux only, time-boxed)**. No recommendation is final; the owner decides.

## Method

OpenSSL 3.0.13 (system headers, Ubuntu 24.04), Lua 5.5.1, GCC. Candidates cloned under
`spikes/OQ-4/` (git-ignored):

- `wahern/luaossl` (MIT, last commit 2026-09-10): built with its own makefile
  (`make all5.5 LUA_APIS=5.5 CPPFLAGS=-I/opt/lua-5.5/include`).
- `zhaozg/lua-openssl` (MIT, last commit 2026-09-20): CMake configure and a direct
  per-file compile attempted.
- Own binding to OpenSSL 3 and mbedTLS: assessed on paper only (mbedTLS is not installed
  in the environment, nothing was built).

## Findings

| Candidate | Lua 5.5.1 build | Fit with the reactor |
|---|---|---|
| luaossl | **builds unmodified**, `openssl.so` produced | TLS stream I/O is not in the Lua API: the only `SSL_new` is used by its `cqueues` integration; the library offers crypto, X.509, contexts (the `openssl.ssl.context` module) but no memory-BIO handshake and read/write calls. Driving it from luv would mean writing the missing part |
| lua-openssl | **not built** within the time-box. CMake 3.28 `find_package(Lua)` fails to locate Lua 5.5 headers even with `LUA_INCLUDE_DIR` set; a direct compile fails on `group.c`/`point.c` (`lua_State` unknown) and the `deps/lua-compat` submodule came back empty from the clone, so the failures may be a checkout problem rather than a 5.5 incompatibility (not verified) | Its sources expose `ssl` objects with `read`, `write`, `handshake`, `pending` and memory BIOs (`src/ssl.c`, `src/bio.c`), which is the shape a luv-driven TLS stream needs |
| Own binding | not built | Full control: SSL object over a memory-BIO pair, owned by the reactor (the reactor reads and writes the socket, the binding only feeds and drains BIOs); API limited to what `hecate.net` needs (client and server contexts, SNI, ALPN, verification, session reuse) |
| mbedTLS | not built | Smaller and static-linking friendly; weaker ecosystem for the certificate-store and ALPN/OCSP needs of an HTTP stack; OpenSSL is the more common choice |

Observations:

- For a luv-based runtime, a **memory-BIO design** (the TLS library never touches the
  socket) is required, regardless of candidate. Both existing bindings are general crypto
  libraries first; neither is a close fit to what `hecate.net` needs, and both carry a
  large API surface to audit (security review scope).
- Licences: all candidates MIT/Apache-style compatible (OpenSSL 3 is Apache-2.0); not a
  discriminator.

## Recommendation

Provisional: write a small own binding to OpenSSL 3 using memory BIOs (about the size of
the OQ-6 binding, plus certificate and verification handling), and keep lua-openssl as a
reference. This needs the owner's decision and an ADR (the dependency on OpenSSL itself
is one either way).

## Not done, to finish before deciding

- Build lua-openssl with a correct checkout (`git submodule update --init`) and a manual
  Lua 5.5 configuration; try an in-process handshake over memory BIOs.
- Prototype the own binding's handshake over a BIO pair and measure.
- macOS and Windows: OpenSSL availability and linking (vcpkg, Homebrew); static linking
  for the self-contained executable (OQ-13).
- mbedTLS build and a size comparison.
