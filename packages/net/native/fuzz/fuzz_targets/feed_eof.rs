#![no_main]
//! The same inputs followed by the end of the transport (truncation handling).
use libfuzzer_sys::fuzz_target;

const CERT: &[u8] = include_bytes!("../../../tests/fixtures/server.pem");
const KEY: &[u8] = include_bytes!("../../../tests/fixtures/server.key");

fuzz_target!(|data: &[u8]| {
    hecate_net_tls_native::fuzzing::client_feed(data, true);
    hecate_net_tls_native::fuzzing::server_feed(CERT, KEY, data, true);
});
