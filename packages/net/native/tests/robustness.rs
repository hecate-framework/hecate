//! A deterministic stand-in for the fuzz targets of `fuzz/`: pseudo-random and mutated inputs go
//! through the same entry points and must never panic (`cargo test` runs it everywhere).

use hecate_net_tls_native::fuzzing;

const SERVER_CERT: &[u8] = include_bytes!("../../tests/fixtures/server.pem");
const SERVER_KEY: &[u8] = include_bytes!("../../tests/fixtures/server.key");

/// xorshift64*: enough randomness for a smoke test, and reproducible from the seed.
struct Rng(u64);

impl Rng {
    fn next(&mut self) -> u64 {
        self.0 ^= self.0 >> 12;
        self.0 ^= self.0 << 25;
        self.0 ^= self.0 >> 27;
        self.0.wrapping_mul(0x2545_F491_4F6C_DD1D)
    }

    fn bytes(&mut self, max: usize) -> Vec<u8> {
        let len = (self.next() as usize) % (max + 1);
        (0..len).map(|_| self.next() as u8).collect()
    }
}

/// A TLS record header followed by random bytes, so that the parsers go past the first check.
fn record_like(rng: &mut Rng) -> Vec<u8> {
    let mut data = vec![0x16, 0x03, 0x01];
    let body = rng.bytes(600);
    data.extend((body.len() as u16).to_be_bytes());
    data.extend(body);
    data
}

#[test]
fn random_input_never_panics_a_session_or_a_parser() {
    let mut rng = Rng(0x00C0_FFEE);
    for _ in 0..300 {
        let data = if rng.next().is_multiple_of(2) {
            rng.bytes(2048)
        } else {
            record_like(&mut rng)
        };
        let eof = rng.next().is_multiple_of(2);
        fuzzing::client_feed(&data, eof);
        fuzzing::server_feed(SERVER_CERT, SERVER_KEY, &data, eof);
        fuzzing::certificates(&data);
        fuzzing::private_key(&data);
    }
}

#[test]
fn a_mutated_pem_never_panics_the_parsers() {
    let mut rng = Rng(42);
    for _ in 0..200 {
        let mut pem = SERVER_CERT.to_vec();
        for _ in 0..4 {
            let at = (rng.next() as usize) % pem.len();
            pem[at] = rng.next() as u8;
        }
        fuzzing::certificates(&pem);
        let mut key = SERVER_KEY.to_vec();
        let at = (rng.next() as usize) % key.len();
        key[at] = rng.next() as u8;
        fuzzing::private_key(&key);
    }
}
