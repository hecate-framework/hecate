# TLS test fixtures

Throwaway test keys, valid for 100 years, never used outside the tests of `hecate.net`:

- `ca.pem`: test CA (its private key was discarded; regenerate the whole set to change it).
- `server.pem` / `server.key`: end-entity certificate for `localhost` and `127.0.0.1`.
- `client.pem` / `client.key`: client certificate (mutual TLS).
- `other_ca.pem`: an unrelated CA, for the untrusted-certificate test.
- `expired_ca.pem`, `expired.pem` / `expired.key`: a CA (key discarded) and a server certificate for
  `localhost` and `127.0.0.1` that expired on 2020-01-02, for the expired-certificate test (made with
  `openssl ca -startdate 20200101000000Z -enddate 20200102000000Z`).
- `variant_ca.pem`: a second test CA (key discarded) that signs the two leaves below.
- `localhost_only.pem` / `localhost_only.key`: valid for the DNS name `localhost` only (no IP address), for the
  default-server-name mismatch test.
- `not_yet_valid.pem` / `not_yet_valid.key`: valid for `localhost` and `127.0.0.1` from 2099-01-01, for the
  not-yet-valid test (made with `openssl ca -startdate 20990101000000Z`).

Regenerate with `openssl req -x509 ...` for the CAs and `openssl x509 -req -CA ...` for the
leaves (ECDSA P-256, `subjectAltName=DNS:localhost,IP:127.0.0.1` on the server).
