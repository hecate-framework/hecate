//! TLS sessions for `hecate.net` (ADR 0021): `rustls` used as a sans-IO state machine.
//!
//! The reactor moves bytes between the socket and a `Session`; this module never touches a
//! socket. Nothing here is `unsafe`; the Lua boundary is `mlua`.
//!
//! Certificate verification is always on (RFC 8446 section 4.4.2; service identity RFC 6125,
//! implemented by rustls-webpki). There is no option to disable it. A client trusts the
//! operating system's store through `rustls-platform-verifier` (ADR 0024), optionally with extra
//! trust anchors of the caller, or only the caller's anchors.

use std::io::{Read, Write};
use std::sync::Arc;

use mlua::prelude::*;
use rustls::pki_types::pem::PemObject;
use rustls::pki_types::{CertificateDer, PrivateKeyDer, ServerName};
use rustls::{
    ClientConfig, ClientConnection, Connection, RootCertStore, ServerConfig, ServerConnection,
};
use rustls_platform_verifier::Verifier;

fn tls_error<E: std::fmt::Display>(what: &str, e: E) -> LuaError {
    LuaError::runtime(format!("{what}: {e}"))
}

fn certificates(pem: &[u8], what: &str) -> LuaResult<Vec<CertificateDer<'static>>> {
    let certs = CertificateDer::pem_slice_iter(pem)
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| tls_error(what, e))?;
    if certs.is_empty() {
        return Err(LuaError::runtime(format!(
            "{what}: no certificate in the PEM data"
        )));
    }
    Ok(certs)
}

fn private_key(pem: &[u8], what: &str) -> LuaResult<PrivateKeyDer<'static>> {
    PrivateKeyDer::from_pem_slice(pem).map_err(|e| tls_error(what, e))
}

fn roots(pem: &[u8], what: &str) -> LuaResult<RootCertStore> {
    let mut store = RootCertStore::empty();
    for cert in certificates(pem, what)? {
        store.add(cert).map_err(|e| tls_error(what, e))?;
    }
    Ok(store)
}

fn alpn_list(table: &LuaTable) -> LuaResult<Vec<Vec<u8>>> {
    match table.get::<Option<Vec<LuaString>>>("alpn")? {
        None => Ok(Vec::new()),
        Some(list) => Ok(list.iter().map(|s| s.as_bytes().to_vec()).collect()),
    }
}

fn opt_bytes(table: &LuaTable, key: &str) -> LuaResult<Option<Vec<u8>>> {
    Ok(table
        .get::<Option<LuaString>>(key)?
        .map(|s| s.as_bytes().to_vec()))
}

/// A client or server TLS configuration, shareable between sessions.
struct Config {
    client: Option<Arc<ClientConfig>>,
    server: Option<Arc<ServerConfig>>,
}

impl LuaUserData for Config {}

/// Largest plaintext chunk `read` returns (one TLS record carries at most 16 KiB).
const MAX_READ: usize = 16384;

/// One TLS connection state machine.
struct Session {
    conn: Connection,
}

impl LuaUserData for Session {
    fn add_methods<M: LuaUserDataMethods<Self>>(methods: &mut M) {
        // feed(bytes) -> consumed. Hands received ciphertext to the session and processes it.
        // May consume fewer bytes than given when plaintext must be read first; feed the rest
        // after `read`. Raises on a TLS protocol error (after which `drain` still yields the
        // alert to send).
        methods.add_method_mut("feed", |_, this, data: LuaString| {
            let bytes = data.as_bytes();
            let mut input: &[u8] = &bytes;
            let mut consumed = 0usize;
            // `wants_read` turns false while plaintext waits to be read (rustls bounds it): stop
            // there and let the caller `read`, then feed the rest.
            while !input.is_empty() && this.conn.wants_read() {
                let n = this
                    .conn
                    .read_tls(&mut input)
                    .map_err(|e| tls_error("tls read", e))?;
                if n == 0 {
                    break;
                }
                consumed += n;
                this.conn
                    .process_new_packets()
                    .map_err(|e| tls_error("tls", e))?;
            }
            Ok(consumed)
        });

        // feed_eof(): the transport ended. Without a prior close_notify a later `read` reports
        // "eof" (a truncation attack cannot pass as a clean end, RFC 8446 section 6.1).
        methods.add_method_mut("feed_eof", |_, this, ()| {
            let mut empty: &[u8] = &[];
            this.conn
                .read_tls(&mut empty)
                .map_err(|e| tls_error("tls read", e))?;
            this.conn
                .process_new_packets()
                .map_err(|e| tls_error("tls", e))?;
            Ok(())
        });

        // drain() -> string. Ciphertext to send to the peer (possibly empty).
        methods.add_method_mut("drain", |lua, this, ()| {
            let mut out = Vec::new();
            while this.conn.wants_write() {
                this.conn
                    .write_tls(&mut out)
                    .map_err(|e| tls_error("tls write", e))?;
            }
            lua.create_string(&out)
        });

        // read(max) -> string | nil, state. Plaintext; on nil the state is "want_read" (nothing
        // buffered yet) or "closed" (the peer sent close_notify, RFC 8446 section 6.1) or
        // "eof" (the transport ended without close_notify: a truncation, not clean).
        methods.add_method_mut("read", |lua, this, max: Option<usize>| {
            // Bounded: `max` comes from Lua and must not size an unbounded allocation.
            let max = max.unwrap_or(MAX_READ).clamp(1, MAX_READ);
            let mut buf = vec![0u8; max];
            match this.conn.reader().read(&mut buf) {
                Ok(0) => Ok((LuaValue::Nil, Some("closed"))),
                Ok(n) => Ok((LuaValue::String(lua.create_string(&buf[..n])?), None)),
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                    Ok((LuaValue::Nil, Some("want_read")))
                }
                Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => {
                    Ok((LuaValue::Nil, Some("eof")))
                }
                Err(e) => Err(tls_error("tls read", e)),
            }
        });

        // write(bytes) -> accepted. Queues plaintext for encryption and returns how many bytes
        // were taken (rustls bounds its send buffer, so call `drain` and write the rest);
        // `drain` yields the ciphertext.
        methods.add_method_mut("write", |_, this, data: LuaString| {
            this.conn
                .writer()
                .write(&data.as_bytes())
                .map_err(|e| tls_error("tls write", e))
        });

        // is_handshaking() -> boolean; wants_write() -> boolean.
        methods.add_method("is_handshaking", |_, this, ()| {
            Ok(this.conn.is_handshaking())
        });
        methods.add_method("wants_write", |_, this, ()| Ok(this.conn.wants_write()));
        methods.add_method("wants_read", |_, this, ()| Ok(this.conn.wants_read()));

        // send_close_notify(): queues the close_notify alert (RFC 8446 section 6.1).
        methods.add_method_mut("send_close_notify", |_, this, ()| {
            this.conn.send_close_notify();
            Ok(())
        });

        // alpn() -> string | nil: the negotiated application protocol (RFC 7301).
        methods.add_method("alpn", |lua, this, ()| match this.conn.alpn_protocol() {
            Some(p) => Ok(Some(lua.create_string(p)?)),
            None => Ok(None),
        });

        // server_name() -> string | nil: the SNI name a client sent (server sessions only).
        methods.add_method("server_name", |_, this, ()| match &this.conn {
            Connection::Server(s) => Ok(s.server_name().map(|n| n.to_string())),
            Connection::Client(_) => Ok(None),
        });

        // version() -> "TLSv1.3" | "TLSv1.2" | nil before the handshake completes.
        methods.add_method("version", |_, this, ()| {
            Ok(this.conn.protocol_version().map(|v| match v {
                rustls::ProtocolVersion::TLSv1_3 => "TLSv1.3".to_string(),
                rustls::ProtocolVersion::TLSv1_2 => "TLSv1.2".to_string(),
                other => format!("{other:?}"),
            }))
        });

        // peer_certificate() -> string | nil: DER of the verified end-entity certificate.
        methods.add_method("peer_certificate", |lua, this, ()| {
            match this.conn.peer_certificates().and_then(|c| c.first()) {
                Some(c) => Ok(Some(lua.create_string(c.as_ref())?)),
                None => Ok(None),
            }
        });
    }
}

/// client_config{ ca_pem?, system_roots?, alpn?, cert_pem?, key_pem? }. By default the server
/// certificate is verified by the operating system (`rustls-platform-verifier`), and `ca_pem`
/// adds trust anchors to the system ones. With `system_roots = false` only `ca_pem` is trusted.
/// There is no way to turn verification off (ADR 0024).
fn client_config(_: &Lua, options: LuaTable) -> LuaResult<Config> {
    let extra = match opt_bytes(&options, "ca_pem")? {
        Some(ca) => Some(certificates(&ca, "client_config ca_pem")?),
        None => None,
    };
    let system_roots = options.get::<Option<bool>>("system_roots")?.unwrap_or(true);
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    let builder = ClientConfig::builder_with_provider(provider.clone())
        .with_safe_default_protocol_versions()
        .map_err(|e| tls_error("client_config", e))?;
    let builder = if system_roots {
        let verifier = Verifier::new_with_extra_roots(extra.unwrap_or_default(), provider)
            .map_err(|e| tls_error("client_config system trust store", e))?;
        // The only custom verifier installed is the platform one: nothing here skips verification.
        builder
            .dangerous()
            .with_custom_certificate_verifier(Arc::new(verifier))
    } else {
        let extra = extra.ok_or_else(|| {
            LuaError::runtime("client_config: ca_pem is required when system_roots is false")
        })?;
        let mut store = RootCertStore::empty();
        for cert in extra {
            store
                .add(cert)
                .map_err(|e| tls_error("client_config ca_pem", e))?;
        }
        builder.with_root_certificates(store)
    };
    let mut config = match (
        opt_bytes(&options, "cert_pem")?,
        opt_bytes(&options, "key_pem")?,
    ) {
        (Some(cert), Some(key)) => builder
            .with_client_auth_cert(
                certificates(&cert, "client_config cert_pem")?,
                private_key(&key, "client_config key_pem")?,
            )
            .map_err(|e| tls_error("client_config", e))?,
        (None, None) => builder.with_no_client_auth(),
        _ => {
            return Err(LuaError::runtime(
                "client_config: cert_pem and key_pem go together",
            ))
        }
    };
    config.alpn_protocols = alpn_list(&options)?;
    Ok(Config {
        client: Some(Arc::new(config)),
        server: None,
    })
}

/// server_config{ cert_pem, key_pem, alpn?, client_ca_pem? }. `client_ca_pem` requires and
/// verifies a client certificate (mutual TLS).
fn server_config(_: &Lua, options: LuaTable) -> LuaResult<Config> {
    let cert = opt_bytes(&options, "cert_pem")?
        .ok_or_else(|| LuaError::runtime("server_config: cert_pem is required"))?;
    let key = opt_bytes(&options, "key_pem")?
        .ok_or_else(|| LuaError::runtime("server_config: key_pem is required"))?;
    let builder =
        ServerConfig::builder_with_provider(Arc::new(rustls::crypto::ring::default_provider()))
            .with_safe_default_protocol_versions()
            .map_err(|e| tls_error("server_config", e))?;
    let builder = match opt_bytes(&options, "client_ca_pem")? {
        Some(ca) => {
            let verifier = rustls::server::WebPkiClientVerifier::builder_with_provider(
                Arc::new(roots(&ca, "server_config client_ca_pem")?),
                Arc::new(rustls::crypto::ring::default_provider()),
            )
            .build()
            .map_err(|e| tls_error("server_config", e))?;
            builder.with_client_cert_verifier(verifier)
        }
        None => builder.with_no_client_auth(),
    };
    let mut config = builder
        .with_single_cert(
            certificates(&cert, "server_config cert_pem")?,
            private_key(&key, "server_config key_pem")?,
        )
        .map_err(|e| tls_error("server_config", e))?;
    config.alpn_protocols = alpn_list(&options)?;
    Ok(Config {
        client: None,
        server: Some(Arc::new(config)),
    })
}

/// client(config, server_name) -> Session. `server_name` is both the SNI name and the identity
/// the certificate must match (RFC 6125); an IP address is matched as an IP address.
fn client(_: &Lua, (config, server_name): (LuaUserDataRef<Config>, String)) -> LuaResult<Session> {
    let cfg = config
        .client
        .clone()
        .ok_or_else(|| LuaError::runtime("client: not a client configuration"))?;
    let name = ServerName::try_from(server_name.clone())
        .map_err(|e| tls_error(&format!("invalid server name {server_name:?}"), e))?;
    let conn = ClientConnection::new(cfg, name).map_err(|e| tls_error("client", e))?;
    Ok(Session {
        conn: Connection::Client(conn),
    })
}

/// server(config) -> Session.
fn server(_: &Lua, config: LuaUserDataRef<Config>) -> LuaResult<Session> {
    let cfg = config
        .server
        .clone()
        .ok_or_else(|| LuaError::runtime("server: not a server configuration"))?;
    let conn = ServerConnection::new(cfg).map_err(|e| tls_error("server", e))?;
    Ok(Session {
        conn: Connection::Server(conn),
    })
}

#[mlua::lua_module(name = "hecate_net_tls_native")]
fn module(lua: &Lua) -> LuaResult<LuaTable> {
    let t = lua.create_table()?;
    t.set("client_config", lua.create_function(client_config)?)?;
    t.set("server_config", lua.create_function(server_config)?)?;
    t.set("client", lua.create_function(client)?)?;
    t.set("server", lua.create_function(server)?)?;
    Ok(t)
}
