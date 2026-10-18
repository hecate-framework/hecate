#![no_main]
//! Ciphertext of arbitrary shape fed to a client and a server session.
use libfuzzer_sys::fuzz_target;

const CERT: &[u8] = include_bytes!("../../../tests/fixtures/server.pem");
const KEY: &[u8] = include_bytes!("../../../tests/fixtures/server.key");

fuzz_target!(|data: &[u8]| {
    hecate_net_tls_native::fuzzing::client_feed(data, false);
    hecate_net_tls_native::fuzzing::server_feed(CERT, KEY, data, false);
});
