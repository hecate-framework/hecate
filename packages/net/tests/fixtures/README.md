# TLS test fixtures

Throwaway test keys, valid for 100 years, never used outside the tests of `hecate.net`:

- `ca.pem`: test CA (its private key was discarded; regenerate the whole set to change it).
- `server.pem` / `server.key`: end-entity certificate for `localhost` and `127.0.0.1`.
- `client.pem` / `client.key`: client certificate (mutual TLS).
- `other_ca.pem`: an unrelated CA, for the untrusted-certificate test.

Regenerate with `openssl req -x509 ...` for the CAs and `openssl x509 -req -CA ...` for the
leaves (ECDSA P-256, `subjectAltName=DNS:localhost,IP:127.0.0.1` on the server).
