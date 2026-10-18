#![no_main]
//! PEM certificate parsing (`ca_pem`, `cert_pem`, `client_ca_pem`).
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    hecate_net_tls_native::fuzzing::certificates(data);
});
