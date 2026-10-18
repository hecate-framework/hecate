#![no_main]
//! PEM private key parsing (`key_pem`).
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    hecate_net_tls_native::fuzzing::private_key(data);
});
