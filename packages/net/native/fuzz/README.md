# Fuzz targets of the native TLS module

`cargo-fuzz` targets for the code that handles bytes from outside: `feed` (ciphertext to a
client and a server session), `feed_eof` (the same, then the end of the transport),
`certificates` and `private_key` (PEM parsing). They are not built by the default build or CI:
they need a nightly toolchain, `cargo install cargo-fuzz` and network access for `libfuzzer-sys`.

```sh
cd packages/net/native
cargo +nightly fuzz run feed            # also: feed_eof, certificates, private_key
cargo +nightly fuzz run feed -- -max_total_time=300
```

`tests/robustness.rs` runs a fixed pseudo-random sample of the same entry points under
`cargo test`, so a panic found by fuzzing is reproduced there with a regression input.
The entry points are `hecate_net_tls_native::fuzzing` (hidden from the documentation).

`build.rs` links the Lua library of the toolchain into the fuzz binaries (the library is a Lua module, whose
Lua symbols the interpreter normally provides): set `LUA_LIB` to its directory, for example
`LUA_LIB=$PWD/../../../.hecate/toolchain/lib`; `LUA_LIB_NAME` and `LUA_LIB_KIND` (`static` or `dylib`) are optional.
