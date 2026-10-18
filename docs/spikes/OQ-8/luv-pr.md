# luv pull request: `reuseport` flag for `uv.tcp_bind` (draft, not submitted)

Prepared for the owner to review and, if wanted, submit under their own name
([OQ-43](../../open-questions.md)). Nothing has been posted anywhere. The change is
[`luv-tcp-reuseport.patch`](luv-tcp-reuseport.patch), made against luv master of 2026-10-01
(`26e62e4`).

## Suggested title

`tcp: add the reuseport bind flag`

## Suggested description

`uv.udp_bind` accepts `reuseport` since libuv's `UV_UDP_REUSEPORT` (and #806 restored the flags
that had been missed). libuv also has `UV_TCP_REUSEPORT` for `uv_tcp_bind` since 1.49.0
(libuv/libuv#4407), but `uv.tcp_bind` only reads `ipv6only`, so a TCP server cannot ask for
`SO_REUSEPORT` and several processes cannot share a listening port with kernel load balancing.

This adds the `reuseport` field to the `flags` table of `uv.tcp_bind`, in the same style as
`ipv6only` and as the UDP flags:

- `src/tcp.c`: reads `reuseport`, guarded by `LUV_UV_VERSION_GEQ(1, 49, 0)` because luv can be
  linked against an older shared libuv (without the guard such a build would not compile).
- `tests/test-tcp.lua`: two servers bind the same port with the flag and both listen; a third
  bind without the flag fails to listen with `EADDRINUSE`. The test returns early when the
  platform or libuv reports the flag unsupported (`ENOTSUP`), so it is safe on macOS and Windows.
- `docs/docs.lua`, regenerated `docs/docs.md` and `docs/meta.lua`: the field, the platform note
  taken from libuv's documentation, and the version note.

Tested: `lua tests/run.lua` against luv built with Lua 5.5 and the bundled libuv 1.53 on Linux, all
tests pass including the new one. Not tested: macOS, Windows, BSD, and builds against an older
shared libuv (the guard is the only protection there).

Measured effect (separate work, not part of this change): four processes that bind one port with
the flag receive evenly spread connections on Linux (largest to smallest 1.05 to 1.13).

## Disclosure

The change and its description were prepared with an AI assistant (Claude) and reviewed and
submitted by a person. Neither luv nor libuv has a written policy on AI-assisted contributions;
the disclosure is made so that reviewers can weigh it.

## Points the owner may want to check before submitting

- The change sets a socket option through libuv and adds no networking logic of its own. The
  security aspect of `SO_REUSEPORT` is libuv's and the kernel's: on Linux only processes with the
  same effective user can bind the same address and port with it, so another user cannot join an
  existing listener.
- libuv documents the flag for Linux 3.9+, DragonFly 3.6+, FreeBSD 12+, Solaris 11.4 and AIX
  7.2.5+. For other platforms it says the call returns an unsupported error; the code of libuv
  (not read here) is the authority.
- luv merges small pull requests quickly and its maintainers prefer one Lua interface (flags in the
  existing table) over `_ex` variants (#797); this change follows that.
