//! TLS sessions for `hecate.net` (ADR 0021): `rustls` used as a sans-IO state machine.
//!
//! The reactor moves bytes between the socket and a `Session`; this module never touches a
//! socket. Nothing here is `unsafe`; the Lua boundary is `mlua`.
//!
//! Certificate verification is always on (RFC 8446 section 4.4.2; service identity RFC 6125,
//! implemented by rustls-webpki). There is no option to disable it. A client trusts the
//! operating system's store through `rustls-platform-verifier` (ADR 0024), optionally with extra
//! trust anchors of the caller, or only the caller's anchors.
//!
//! # Errors
//!
//! A failure raised to Lua is a string. When the cause is a `rustls::Error` variant that callers
//! tell apart, the string starts with its kind in brackets, `[untrusted_issuer] tls: ...`; the
//! kinds are `untrusted_issuer`, `name_mismatch`, `not_yet_valid`, `expired`, `revoked` and
//! `alpn_mismatch`. The kind comes from the error variant, never from its text. `hecate.net`
//! strips the prefix and stores the kind in `TlsError.context.reason`; an error without a prefix
//! (the operating system's verifier on macOS and Windows reports many failures as text only) is
//! classified from its text there.

use std::io::{Read, Write};
use std::sync::Arc;

use mlua::prelude::*;
use rustls::pki_types::pem::PemObject;
use rustls::pki_types::{CertificateDer, PrivateKeyDer, ServerName};
use rustls::{
    CertificateError, ClientConfig, ClientConnection, Connection, Error as TlsFailure,
    RootCertStore, ServerConfig, ServerConnection,
};
use rustls_platform_verifier::Verifier;

/// Largest plaintext chunk `read` returns (one TLS record carries at most 16 KiB).
const MAX_READ: usize = 16384;

/// Longest ALPN protocol name (RFC 7301 section 3.1: a one-byte length).
const MAX_ALPN: usize = 255;

fn tls_error<E: std::fmt::Display>(what: &str, e: E) -> LuaError {
    LuaError::runtime(format!("{what}: {e}"))
}

/// The kind of a rustls failure that callers tell apart, derived from the variant (not the text).
fn failure_kind(e: &TlsFailure) -> Option<&'static str> {
    match e {
        TlsFailure::InvalidCertificate(c) => match c {
            CertificateError::UnknownIssuer => Some("untrusted_issuer"),
            CertificateError::NotValidForName | CertificateError::NotValidForNameContext { .. } => {
                Some("name_mismatch")
            }
            CertificateError::NotValidYet | CertificateError::NotValidYetContext { .. } => {
                Some("not_yet_valid")
            }
            CertificateError::Expired | CertificateError::ExpiredContext { .. } => Some("expired"),
            CertificateError::Revoked => Some("revoked"),
            _ => None,
        },
        TlsFailure::NoApplicationProtocol => Some("alpn_mismatch"),
        TlsFailure::AlertReceived(rustls::AlertDescription::NoApplicationProtocol) => {
            Some("alpn_mismatch")
        }
        _ => None,
    }
}

/// A raised failure: `[kind] what: error` when the variant has a kind, else `what: error`.
fn tls_failure(what: &str, e: &TlsFailure) -> LuaError {
    match failure_kind(e) {
        Some(kind) => LuaError::runtime(format!("[{kind}] {what}: {e}")),
        None => tls_error(what, e),
    }
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

/// Checks the protocol names of the `alpn` option: 1 to 255 bytes each (RFC 7301 section 3.1).
fn check_alpn(list: Vec<Vec<u8>>, what: &str) -> LuaResult<Vec<Vec<u8>>> {
    for name in &list {
        if name.is_empty() || name.len() > MAX_ALPN {
            return Err(LuaError::runtime(format!(
                "{what}: option alpn: each protocol name must be 1 to {MAX_ALPN} bytes, got {}",
                name.len()
            )));
        }
    }
    Ok(list)
}

fn alpn_list(table: &LuaTable, what: &str) -> LuaResult<Vec<Vec<u8>>> {
    let list = match table.get::<LuaValue>("alpn")? {
        LuaValue::Nil => return Ok(Vec::new()),
        LuaValue::Table(list) => list,
        _ => {
            return Err(LuaError::runtime(format!(
                "{what}: option alpn must be a list of strings"
            )))
        }
    };
    let mut names = Vec::new();
    for item in list.sequence_values::<LuaValue>() {
        match item? {
            LuaValue::String(s) => names.push(s.as_bytes().to_vec()),
            _ => {
                return Err(LuaError::runtime(format!(
                    "{what}: option alpn must be a list of strings"
                )))
            }
        }
    }
    check_alpn(names, what)
}

fn opt_bytes(table: &LuaTable, key: &str) -> LuaResult<Option<Vec<u8>>> {
    Ok(table
        .get::<Option<LuaString>>(key)?
        .map(|s| s.as_bytes().to_vec()))
}

/// A client or server TLS configuration, shareable between sessions. `close` (and `<close>`)
/// drops it; sessions already built from it keep their own reference.
struct Config {
    client: Option<Arc<ClientConfig>>,
    server: Option<Arc<ServerConfig>>,
}

impl LuaUserData for Config {
    fn add_methods<M: LuaUserDataMethods<Self>>(methods: &mut M) {
        methods.add_method_mut("close", |_, this, ()| {
            this.client = None;
            this.server = None;
            Ok(())
        });
        methods.add_meta_method_mut(LuaMetaMethod::Close, |_, this, _: LuaValue| {
            this.client = None;
            this.server = None;
            Ok(())
        });
    }
}

/// What `Session::read` found.
#[derive(Debug, PartialEq)]
enum Outcome {
    /// This many plaintext bytes are in the scratch buffer.
    Data(usize),
    /// The peer sent `close_notify` (RFC 8446 section 6.1): a clean end.
    Closed,
    /// Nothing buffered: feed more ciphertext.
    WantRead,
    /// The transport ended without `close_notify`: a truncation, not a clean end.
    Eof,
}

/// One TLS connection state machine.
struct Session {
    /// None once closed.
    conn: Option<Connection>,
    /// Plaintext handed out by `read`, reused between calls.
    scratch: Vec<u8>,
    /// The transport ended while plaintext was still waiting to be read: rustls refuses further
    /// input then, so the end is applied once that plaintext has been read.
    pending_eof: bool,
}

impl Session {
    fn new(conn: Connection) -> Self {
        Session {
            conn: Some(conn),
            scratch: Vec::new(),
            pending_eof: false,
        }
    }

    fn conn(&mut self) -> LuaResult<&mut Connection> {
        self.conn
            .as_mut()
            .ok_or_else(|| LuaError::runtime("the TLS session is closed"))
    }

    /// Processes what `read_tls` buffered, raising rustls failures with their kind.
    fn process(conn: &mut Connection) -> LuaResult<()> {
        conn.process_new_packets()
            .map(|_| ())
            .map_err(|e| tls_failure("tls", &e))
    }

    /// Hands received ciphertext to the session and processes it. May consume fewer bytes than
    /// given when plaintext must be read first; feed the rest after `read`. Raises on a TLS
    /// protocol error (after which `drain` still yields the alert to send).
    fn feed(&mut self, bytes: &[u8]) -> LuaResult<usize> {
        let conn = self.conn()?;
        let mut input = bytes;
        let mut consumed = 0usize;
        // `wants_read` turns false while plaintext waits to be read (rustls bounds it): stop
        // there and let the caller `read`, then feed the rest.
        while !input.is_empty() && conn.wants_read() {
            let n = conn
                .read_tls(&mut input)
                .map_err(|e| tls_error("tls read", e))?;
            if n == 0 {
                break;
            }
            consumed += n;
            Self::process(conn)?;
        }
        Ok(consumed)
    }

    /// The transport ended. Without a prior `close_notify` a later `read` reports `Eof` (a
    /// truncation attack cannot pass as a clean end, RFC 8446 section 6.1).
    fn feed_eof(&mut self) -> LuaResult<()> {
        self.pending_eof = true;
        self.apply_eof()
    }

    /// Applies a recorded end of the transport once rustls accepts input again. rustls 0.23
    /// (`read_tls`, conn.rs) fails with "received plaintext buffer full" while more than 16 KiB
    /// of plaintext is pending, even for the empty read that signals the end, hence the wait.
    fn apply_eof(&mut self) -> LuaResult<()> {
        if !self.pending_eof {
            return Ok(());
        }
        let Some(conn) = self.conn.as_mut() else {
            return Ok(());
        };
        if !conn.wants_read() {
            return Ok(());
        }
        self.pending_eof = false;
        let mut empty: &[u8] = &[];
        conn.read_tls(&mut empty)
            .map_err(|e| tls_error("tls read", e))?;
        Self::process(conn)
    }

    /// Ciphertext to send to the peer (possibly empty).
    fn drain(&mut self) -> LuaResult<Vec<u8>> {
        let conn = self.conn()?;
        let mut out = Vec::new();
        while conn.wants_write() {
            let n = conn
                .write_tls(&mut out)
                .map_err(|e| tls_error("tls write", e))?;
            if n == 0 {
                break;
            }
        }
        Ok(out)
    }

    /// Reads at most `max` plaintext bytes into the scratch buffer.
    fn read(&mut self, max: usize) -> LuaResult<Outcome> {
        // Bounded: `max` comes from Lua and must not size an unbounded allocation.
        let max = max.clamp(1, MAX_READ);
        if self.scratch.len() < MAX_READ {
            self.scratch.resize(MAX_READ, 0);
        }
        loop {
            let conn = self
                .conn
                .as_mut()
                .ok_or_else(|| LuaError::runtime("the TLS session is closed"))?;
            match conn.reader().read(&mut self.scratch[..max]) {
                Ok(0) => return Ok(Outcome::Closed),
                Ok(n) => return Ok(Outcome::Data(n)),
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                    if self.pending_eof {
                        self.apply_eof()?;
                        if !self.pending_eof {
                            continue;
                        }
                    }
                    return Ok(Outcome::WantRead);
                }
                Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => return Ok(Outcome::Eof),
                Err(e) => return Err(tls_error("tls read", e)),
            }
        }
    }

    /// Queues plaintext from `offset` (a byte count to skip) for encryption and returns how many
    /// bytes were taken. It returns 0, which is not an error, when the session takes nothing now:
    /// its send buffer is full (`drain`, send, call again) or it was shut down.
    fn write(&mut self, data: &[u8], offset: usize) -> LuaResult<usize> {
        let rest = data
            .get(offset..)
            .ok_or_else(|| LuaError::runtime("tls write: offset is beyond the data"))?;
        self.conn()?
            .writer()
            .write(rest)
            .map_err(|e| tls_error("tls write", e))
    }

    /// Drops the connection state; every later operation raises. Idempotent.
    fn close(&mut self) {
        self.conn = None;
        self.scratch = Vec::new();
        self.pending_eof = false;
    }
}

impl LuaUserData for Session {
    fn add_methods<M: LuaUserDataMethods<Self>>(methods: &mut M) {
        // feed(bytes) -> consumed.
        methods.add_method_mut("feed", |_, this, data: LuaString| {
            this.feed(&data.as_bytes())
        });

        // feed_eof(): the transport ended.
        methods.add_method_mut("feed_eof", |_, this, ()| this.feed_eof());

        // drain() -> string. Ciphertext to send to the peer (possibly empty).
        methods.add_method_mut("drain", |lua, this, ()| {
            let out = this.drain()?;
            lua.create_string(&out)
        });

        // read(max) -> string | nil, state. Plaintext; on nil the state is "want_read" (nothing
        // buffered yet) or "closed" (the peer sent close_notify, RFC 8446 section 6.1) or
        // "eof" (the transport ended without close_notify: a truncation, not clean).
        methods.add_method_mut("read", |lua, this, max: Option<usize>| {
            match this.read(max.unwrap_or(MAX_READ))? {
                Outcome::Data(n) => Ok((
                    LuaValue::String(lua.create_string(&this.scratch[..n])?),
                    None,
                )),
                Outcome::Closed => Ok((LuaValue::Nil, Some("closed"))),
                Outcome::WantRead => Ok((LuaValue::Nil, Some("want_read"))),
                Outcome::Eof => Ok((LuaValue::Nil, Some("eof"))),
            }
        });

        // write(bytes, offset?) -> accepted. Queues the plaintext after the first `offset` bytes
        // (default 0) and returns how many bytes were taken: rustls bounds its send buffer, so
        // call `drain`, send, and write the rest with a larger offset. It returns 0 (not an error)
        // when nothing fits now or after `send_close_notify`.
        methods.add_method_mut(
            "write",
            |_, this, (data, offset): (LuaString, Option<usize>)| {
                this.write(&data.as_bytes(), offset.unwrap_or(0))
            },
        );

        // is_handshaking() -> boolean; wants_write() -> boolean; wants_read() -> boolean. All
        // false once the session is closed.
        methods.add_method("is_handshaking", |_, this, ()| {
            Ok(this.conn.as_ref().is_some_and(|c| c.is_handshaking()))
        });
        methods.add_method("wants_write", |_, this, ()| {
            Ok(this.conn.as_ref().is_some_and(|c| c.wants_write()))
        });
        methods.add_method("wants_read", |_, this, ()| {
            Ok(this.conn.as_ref().is_some_and(|c| c.wants_read()))
        });

        // send_close_notify(): queues the close_notify alert (RFC 8446 section 6.1).
        methods.add_method_mut("send_close_notify", |_, this, ()| {
            this.conn()?.send_close_notify();
            Ok(())
        });

        // alpn() -> string | nil: the negotiated application protocol (RFC 7301).
        methods.add_method("alpn", |lua, this, ()| {
            match this.conn.as_ref().and_then(|c| c.alpn_protocol()) {
                Some(p) => Ok(Some(lua.create_string(p)?)),
                None => Ok(None),
            }
        });

        // server_name() -> string | nil: the SNI name a client sent (server sessions only).
        methods.add_method("server_name", |_, this, ()| match &this.conn {
            Some(Connection::Server(s)) => Ok(s.server_name().map(|n| n.to_string())),
            _ => Ok(None),
        });

        // version() -> "TLSv1.3" | "TLSv1.2" | nil before the handshake completes.
        methods.add_method("version", |_, this, ()| {
            Ok(this
                .conn
                .as_ref()
                .and_then(|c| c.protocol_version())
                .map(|v| match v {
                    rustls::ProtocolVersion::TLSv1_3 => "TLSv1.3".to_string(),
                    rustls::ProtocolVersion::TLSv1_2 => "TLSv1.2".to_string(),
                    other => format!("{other:?}"),
                }))
        });

        // peer_certificate() -> string | nil: DER of the verified end-entity certificate.
        methods.add_method("peer_certificate", |lua, this, ()| {
            match this
                .conn
                .as_ref()
                .and_then(|c| c.peer_certificates())
                .and_then(|c| c.first())
            {
                Some(c) => Ok(Some(lua.create_string(c.as_ref())?)),
                None => Ok(None),
            }
        });

        // close(): drops the connection state. Idempotent; later operations raise.
        methods.add_method_mut("close", |_, this, ()| {
            this.close();
            Ok(())
        });
        methods.add_meta_method_mut(LuaMetaMethod::Close, |_, this, _: LuaValue| {
            this.close();
            Ok(())
        });
    }
}

/// What `client_config` needs, extracted from the Lua options.
struct ClientParams {
    ca_pem: Option<Vec<u8>>,
    system_roots: bool,
    cert_pem: Option<Vec<u8>>,
    key_pem: Option<Vec<u8>>,
    alpn: Vec<Vec<u8>>,
}

fn build_client(p: ClientParams) -> LuaResult<Arc<ClientConfig>> {
    let alpn = check_alpn(p.alpn, "client_config")?;
    let extra = match &p.ca_pem {
        Some(ca) => Some(certificates(ca, "client_config ca_pem")?),
        None => None,
    };
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    let builder = ClientConfig::builder_with_provider(provider.clone())
        .with_safe_default_protocol_versions()
        .map_err(|e| tls_error("client_config", e))?;
    let builder = if p.system_roots {
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
    let mut config = match (p.cert_pem, p.key_pem) {
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
    config.alpn_protocols = alpn;
    Ok(Arc::new(config))
}

/// client_config{ ca_pem?, system_roots?, alpn?, cert_pem?, key_pem? }. By default the server
/// certificate is verified by the operating system (`rustls-platform-verifier`), and `ca_pem`
/// adds trust anchors to the system ones. With `system_roots = false` only `ca_pem` is trusted.
/// There is no way to turn verification off (ADR 0024).
fn client_config(_: &Lua, options: LuaTable) -> LuaResult<Config> {
    let params = ClientParams {
        ca_pem: opt_bytes(&options, "ca_pem")?,
        system_roots: options.get::<Option<bool>>("system_roots")?.unwrap_or(true),
        cert_pem: opt_bytes(&options, "cert_pem")?,
        key_pem: opt_bytes(&options, "key_pem")?,
        alpn: alpn_list(&options, "client_config")?,
    };
    Ok(Config {
        client: Some(build_client(params)?),
        server: None,
    })
}

/// What `server_config` needs, extracted from the Lua options.
struct ServerParams {
    cert_pem: Vec<u8>,
    key_pem: Vec<u8>,
    client_ca_pem: Option<Vec<u8>>,
    alpn: Vec<Vec<u8>>,
}

fn build_server(p: ServerParams) -> LuaResult<Arc<ServerConfig>> {
    let alpn = check_alpn(p.alpn, "server_config")?;
    let builder =
        ServerConfig::builder_with_provider(Arc::new(rustls::crypto::ring::default_provider()))
            .with_safe_default_protocol_versions()
            .map_err(|e| tls_error("server_config", e))?;
    let builder = match &p.client_ca_pem {
        Some(ca) => {
            let verifier = rustls::server::WebPkiClientVerifier::builder_with_provider(
                Arc::new(roots(ca, "server_config client_ca_pem")?),
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
            certificates(&p.cert_pem, "server_config cert_pem")?,
            private_key(&p.key_pem, "server_config key_pem")?,
        )
        .map_err(|e| tls_error("server_config", e))?;
    config.alpn_protocols = alpn;
    Ok(Arc::new(config))
}

/// server_config{ cert_pem, key_pem, alpn?, client_ca_pem? }. `client_ca_pem` requires and
/// verifies a client certificate (mutual TLS). Client certificate revocation is not checked:
/// no CRLs are configured (see docs/open-questions.md).
fn server_config(_: &Lua, options: LuaTable) -> LuaResult<Config> {
    let params = ServerParams {
        cert_pem: opt_bytes(&options, "cert_pem")?
            .ok_or_else(|| LuaError::runtime("server_config: cert_pem is required"))?,
        key_pem: opt_bytes(&options, "key_pem")?
            .ok_or_else(|| LuaError::runtime("server_config: key_pem is required"))?,
        client_ca_pem: opt_bytes(&options, "client_ca_pem")?,
        alpn: alpn_list(&options, "server_config")?,
    };
    Ok(Config {
        client: None,
        server: Some(build_server(params)?),
    })
}

fn new_client_session(cfg: Arc<ClientConfig>, server_name: &str) -> LuaResult<Session> {
    let name = ServerName::try_from(server_name.to_string())
        .map_err(|e| tls_error(&format!("invalid server name {server_name:?}"), e))?;
    let conn = ClientConnection::new(cfg, name).map_err(|e| tls_error("client", e))?;
    Ok(Session::new(Connection::Client(conn)))
}

fn new_server_session(cfg: Arc<ServerConfig>) -> LuaResult<Session> {
    let conn = ServerConnection::new(cfg).map_err(|e| tls_error("server", e))?;
    Ok(Session::new(Connection::Server(conn)))
}

/// client(config, server_name) -> Session. `server_name` is both the SNI name and the identity
/// the certificate must match (RFC 6125); an IP address is matched as an IP address.
fn client(_: &Lua, (config, server_name): (LuaUserDataRef<Config>, String)) -> LuaResult<Session> {
    let cfg = config.client.clone().ok_or_else(|| {
        LuaError::runtime("client: not a client configuration (or it was closed)")
    })?;
    new_client_session(cfg, &server_name)
}

/// server(config) -> Session.
fn server(_: &Lua, config: LuaUserDataRef<Config>) -> LuaResult<Session> {
    let cfg = config.server.clone().ok_or_else(|| {
        LuaError::runtime("server: not a server configuration (or it was closed)")
    })?;
    new_server_session(cfg)
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

/// Entry points for the fuzz targets of `fuzz/` and the robustness test: they feed arbitrary
/// bytes to the parsers and sessions and must never panic. Not part of the Lua interface.
#[doc(hidden)]
pub mod fuzzing {
    use super::*;

    /// Parses PEM certificates; returns how many were found.
    pub fn certificates(pem: &[u8]) -> usize {
        super::certificates(pem, "fuzz").map_or(0, |c| c.len())
    }

    /// Parses a PEM private key; returns whether one was found.
    pub fn private_key(pem: &[u8]) -> bool {
        super::private_key(pem, "fuzz").is_ok()
    }

    fn run(mut session: Session, data: &[u8], eof: bool) {
        let mut rest = data;
        for _ in 0..64 {
            if rest.is_empty() {
                break;
            }
            match session.feed(rest) {
                Ok(0) => {
                    while let Ok(Outcome::Data(_)) = session.read(MAX_READ) {}
                    if session.feed(rest).map_or(true, |n| n == 0) {
                        break;
                    }
                }
                Ok(n) => rest = &rest[n..],
                Err(_) => {
                    let _ = session.drain();
                    return;
                }
            }
        }
        if eof {
            let _ = session.feed_eof();
        }
        let _ = session.drain();
        while let Ok(Outcome::Data(_)) = session.read(MAX_READ) {}
    }

    /// Feeds `data` to a client that trusts no certificate, then optionally the end of the transport.
    pub fn client_feed(data: &[u8], eof: bool) {
        let provider = Arc::new(rustls::crypto::ring::default_provider());
        let Ok(builder) =
            ClientConfig::builder_with_provider(provider).with_safe_default_protocol_versions()
        else {
            return;
        };
        let config = builder
            .with_root_certificates(RootCertStore::empty())
            .with_no_client_auth();
        if let Ok(session) = new_client_session(Arc::new(config), "localhost") {
            run(session, data, eof);
        }
    }

    /// Feeds `data` to a server with the given certificate and key.
    pub fn server_feed(cert_pem: &[u8], key_pem: &[u8], data: &[u8], eof: bool) {
        let Ok(config) = build_server(ServerParams {
            cert_pem: cert_pem.to_vec(),
            key_pem: key_pem.to_vec(),
            client_ca_pem: None,
            alpn: Vec::new(),
        }) else {
            return;
        };
        if let Ok(session) = new_server_session(config) {
            run(session, data, eof);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const CA: &[u8] = include_bytes!("../../tests/fixtures/ca.pem");
    const OTHER_CA: &[u8] = include_bytes!("../../tests/fixtures/other_ca.pem");
    const SERVER_CERT: &[u8] = include_bytes!("../../tests/fixtures/server.pem");
    const SERVER_KEY: &[u8] = include_bytes!("../../tests/fixtures/server.key");
    const EXPIRED_CA: &[u8] = include_bytes!("../../tests/fixtures/expired_ca.pem");
    const EXPIRED_CERT: &[u8] = include_bytes!("../../tests/fixtures/expired.pem");
    const EXPIRED_KEY: &[u8] = include_bytes!("../../tests/fixtures/expired.key");
    const VARIANT_CA: &[u8] = include_bytes!("../../tests/fixtures/variant_ca.pem");
    const NOT_YET_CERT: &[u8] = include_bytes!("../../tests/fixtures/not_yet_valid.pem");
    const NOT_YET_KEY: &[u8] = include_bytes!("../../tests/fixtures/not_yet_valid.key");

    fn names(list: &[&str]) -> Vec<Vec<u8>> {
        list.iter().map(|s| s.as_bytes().to_vec()).collect()
    }

    fn client_with(ca: &[u8], server_name: &str, alpn: &[&str]) -> Session {
        let config = build_client(ClientParams {
            ca_pem: Some(ca.to_vec()),
            system_roots: false,
            cert_pem: None,
            key_pem: None,
            alpn: names(alpn),
        })
        .unwrap();
        new_client_session(config, server_name).unwrap()
    }

    fn server_with(cert: &[u8], key: &[u8], alpn: &[&str]) -> Session {
        let config = build_server(ServerParams {
            cert_pem: cert.to_vec(),
            key_pem: key.to_vec(),
            client_ca_pem: None,
            alpn: names(alpn),
        })
        .unwrap();
        new_server_session(config).unwrap()
    }

    fn pair() -> (Session, Session) {
        (
            client_with(CA, "localhost", &[]),
            server_with(SERVER_CERT, SERVER_KEY, &[]),
        )
    }

    /// Both directions of an in-memory connection: ciphertext queued and not yet consumed.
    #[derive(Default)]
    struct Wire {
        to_server: Vec<u8>,
        to_client: Vec<u8>,
    }

    /// Moves what `from` queued into `wire`, then feeds `to` at most `step` bytes at a time for as
    /// long as it consumes them.
    fn transfer(
        from: &mut Session,
        to: &mut Session,
        wire: &mut Vec<u8>,
        step: usize,
    ) -> LuaResult<()> {
        wire.extend(from.drain()?);
        while !wire.is_empty() {
            let end = step.min(wire.len());
            let n = to.feed(&wire[..end])?;
            if n == 0 {
                break; // the session wants to send or to be read first
            }
            wire.drain(..n);
        }
        Ok(())
    }

    fn handshake_in(client: &mut Session, server: &mut Session, step: usize) -> LuaResult<()> {
        let mut wire = Wire::default();
        for _ in 0..100_000 {
            transfer(client, server, &mut wire.to_server, step)?;
            transfer(server, client, &mut wire.to_client, step)?;
            if !client.conn().unwrap().is_handshaking() && !server.conn().unwrap().is_handshaking()
            {
                return Ok(());
            }
        }
        panic!("the handshake did not finish");
    }

    /// Sends everything `from` queued to `to` (after the handshake nothing is held back).
    fn deliver(from: &mut Session, to: &mut Session) {
        let mut wire = Vec::new();
        transfer(from, to, &mut wire, usize::MAX).unwrap();
        assert!(wire.is_empty());
    }

    fn read_all(session: &mut Session) -> Vec<u8> {
        let mut all = Vec::new();
        while let Outcome::Data(n) = session.read(MAX_READ).unwrap() {
            all.extend_from_slice(&session.scratch[..n]);
        }
        all
    }

    /// The message Lua sees (without mlua's "runtime error: " display prefix).
    fn message(e: LuaError) -> String {
        match e {
            LuaError::RuntimeError(m) => m,
            other => panic!("unexpected error {other}"),
        }
    }

    fn failure_text(r: LuaResult<()>) -> String {
        message(r.expect_err("the handshake should fail"))
    }

    #[test]
    fn a_certificate_chain_is_parsed() {
        assert_eq!(certificates(SERVER_CERT, "test").unwrap().len(), 1);
    }

    #[test]
    fn pem_without_a_certificate_is_an_error_that_names_the_option() {
        let err = certificates(b"not pem at all", "client_config ca_pem").unwrap_err();
        assert!(err.to_string().contains("client_config ca_pem"), "{err}");
    }

    #[test]
    fn a_private_key_is_parsed_from_pem_and_text_without_one_is_refused() {
        assert!(private_key(SERVER_KEY, "test").is_ok());
        assert!(private_key(b"not pem at all", "test").is_err());
        assert!(private_key(b"", "test").is_err());
    }

    #[test]
    fn trust_anchors_are_loaded_from_pem() {
        assert_eq!(roots(CA, "test").unwrap().len(), 1);
        assert!(roots(b"", "test").is_err());
    }

    #[test]
    fn a_read_is_never_larger_than_one_tls_record() {
        assert_eq!(MAX_READ, 16384);
        assert_eq!(usize::MAX.clamp(1, MAX_READ), MAX_READ);
        assert_eq!(0usize.clamp(1, MAX_READ), 1);
    }

    #[test]
    fn alpn_names_must_be_one_to_255_bytes_and_the_error_names_the_option() {
        assert!(check_alpn(names(&["h2", "http/1.1"]), "client_config").is_ok());
        assert!(check_alpn(vec![vec![b'a'; 255]], "client_config").is_ok());
        for bad in [vec![Vec::new()], vec![vec![b'a'; 256]]] {
            let err = check_alpn(bad, "server_config").unwrap_err().to_string();
            assert!(
                err.contains("server_config") && err.contains("alpn"),
                "{err}"
            );
        }
    }

    #[test]
    fn a_configuration_with_an_invalid_alpn_name_is_refused() {
        let err = build_server(ServerParams {
            cert_pem: SERVER_CERT.to_vec(),
            key_pem: SERVER_KEY.to_vec(),
            client_ca_pem: None,
            alpn: vec![Vec::new()],
        })
        .expect_err("an empty protocol name is refused");
        assert!(err.to_string().contains("alpn"), "{err}");
    }

    #[test]
    fn a_handshake_in_memory_negotiates_alpn_and_carries_data_both_ways() {
        let mut client = client_with(CA, "localhost", &["http/1.1"]);
        let mut server = server_with(SERVER_CERT, SERVER_KEY, &["h2", "http/1.1"]);
        handshake_in(&mut client, &mut server, usize::MAX).unwrap();
        assert_eq!(
            client.conn().unwrap().alpn_protocol(),
            Some(&b"http/1.1"[..])
        );
        assert_eq!(client.write(b"ping", 0).unwrap(), 4);
        deliver(&mut client, &mut server);
        assert_eq!(read_all(&mut server), b"ping");
        assert_eq!(server.write(b"pong", 0).unwrap(), 4);
        deliver(&mut server, &mut client);
        assert_eq!(read_all(&mut client), b"pong");
        assert_eq!(client.read(1).unwrap(), Outcome::WantRead);
    }

    #[test]
    fn a_handshake_fed_one_byte_at_a_time_completes() {
        let (mut client, mut server) = pair();
        handshake_in(&mut client, &mut server, 1).unwrap();
        client.write(b"x", 0).unwrap();
        deliver(&mut client, &mut server);
        assert_eq!(read_all(&mut server), b"x");
    }

    #[test]
    fn close_notify_is_a_clean_end_and_a_bare_end_of_transport_is_a_truncation() {
        let (mut client, mut server) = pair();
        handshake_in(&mut client, &mut server, usize::MAX).unwrap();
        server.write(b"data", 0).unwrap();
        server.conn().unwrap().send_close_notify();
        deliver(&mut server, &mut client);
        assert_eq!(read_all(&mut client), b"data");
        assert_eq!(client.read(16).unwrap(), Outcome::Closed);
        // The transport ending after close_notify changes nothing.
        client.feed_eof().unwrap();
        assert_eq!(client.read(16).unwrap(), Outcome::Closed);

        let (mut client, mut server) = pair();
        handshake_in(&mut client, &mut server, usize::MAX).unwrap();
        server.write(b"data", 0).unwrap();
        deliver(&mut server, &mut client);
        client.feed_eof().unwrap();
        assert_eq!(read_all(&mut client), b"data");
        assert_eq!(client.read(16).unwrap(), Outcome::Eof);
    }

    #[test]
    fn the_end_of_the_transport_waits_for_plaintext_above_the_buffer_limit() {
        // rustls 0.23 `read_tls` fails with "received plaintext buffer full" while more than
        // 16 KiB of plaintext is pending, even for the empty read of the end of the transport.
        let (mut client, mut server) = pair();
        handshake_in(&mut client, &mut server, usize::MAX).unwrap();
        // One full record followed by small ones: the 4 KiB reads of rustls then end inside the
        // first record and the last read completes it together with the small records, so more
        // than 16 KiB of plaintext is pending although `feed` honoured `wants_read`.
        let mut payload = vec![7u8; 16_384];
        payload.extend(vec![9u8; 1_000]);
        let mut wire = Vec::new();
        let mut lengths = vec![16_384];
        lengths.extend([100; 10]);
        let mut at = 0;
        for len in lengths {
            let piece = &payload[at..at + len];
            at += len;
            assert_eq!(server.write(piece, 0).unwrap(), len);
            wire.extend(server.drain().unwrap());
        }
        let mut rest = &wire[..];
        while client.conn().unwrap().wants_read() && !rest.is_empty() {
            let n = client.feed(rest).unwrap();
            rest = &rest[n..];
        }
        client
            .feed_eof()
            .expect("the end of the transport is recorded, not an error");
        let mut got = Vec::new();
        loop {
            got.extend(read_all(&mut client));
            if rest.is_empty() {
                break;
            }
            let n = client.feed(rest).unwrap();
            assert!(n > 0);
            rest = &rest[n..];
        }
        assert_eq!(got, payload);
        // Without close_notify the end is a truncation, reported once the plaintext is read.
        assert_eq!(client.read(16).unwrap(), Outcome::Eof);
    }

    #[test]
    fn write_takes_from_an_offset_reports_zero_when_nothing_fits_and_refuses_a_bad_offset() {
        let (mut client, mut server) = pair();
        handshake_in(&mut client, &mut server, usize::MAX).unwrap();
        assert_eq!(client.write(b"abcdef", 2).unwrap(), 4);
        deliver(&mut client, &mut server);
        assert_eq!(read_all(&mut server), b"cdef");
        assert_eq!(client.write(b"abc", 3).unwrap(), 0);
        assert!(client.write(b"abc", 4).is_err());
        // Without draining, the bounded send buffer takes part of a large write and then nothing.
        let big = vec![1u8; 1 << 20];
        let first = client.write(&big, 0).unwrap();
        assert!(first > 0 && first < big.len());
        assert_eq!(client.write(&big, first).unwrap(), 0);
    }

    #[test]
    fn failures_carry_a_kind_taken_from_the_error_variant() {
        let mut client = client_with(OTHER_CA, "localhost", &[]);
        let mut server = server_with(SERVER_CERT, SERVER_KEY, &[]);
        let text = failure_text(handshake_in(&mut client, &mut server, usize::MAX));
        assert!(text.starts_with("[untrusted_issuer] "), "{text}");

        let mut client = client_with(CA, "wrong.example", &[]);
        let mut server = server_with(SERVER_CERT, SERVER_KEY, &[]);
        let text = failure_text(handshake_in(&mut client, &mut server, usize::MAX));
        assert!(text.starts_with("[name_mismatch] "), "{text}");

        let mut client = client_with(EXPIRED_CA, "localhost", &[]);
        let mut server = server_with(EXPIRED_CERT, EXPIRED_KEY, &[]);
        let text = failure_text(handshake_in(&mut client, &mut server, usize::MAX));
        assert!(text.starts_with("[expired] "), "{text}");

        let mut client = client_with(VARIANT_CA, "localhost", &[]);
        let mut server = server_with(NOT_YET_CERT, NOT_YET_KEY, &[]);
        let text = failure_text(handshake_in(&mut client, &mut server, usize::MAX));
        assert!(text.starts_with("[not_yet_valid] "), "{text}");

        let mut client = client_with(CA, "localhost", &["http/1.1"]);
        let mut server = server_with(SERVER_CERT, SERVER_KEY, &["h2"]);
        let text = failure_text(handshake_in(&mut client, &mut server, usize::MAX));
        assert!(text.starts_with("[alpn_mismatch] "), "{text}");
    }

    #[test]
    fn a_failure_without_a_kind_has_no_prefix() {
        let (_, mut server) = pair();
        let err = message(
            server
                .feed(&[0x16, 0x03, 0x01, 0x00, 0x05, 1, 2, 3, 4, 5])
                .unwrap_err(),
        );
        assert!(err.starts_with("tls: "), "{err}");
    }

    #[test]
    fn a_closed_session_drops_its_state_and_raises_afterwards() {
        let (mut client, _) = pair();
        client.close();
        client.close();
        assert!(client.conn.is_none());
        assert!(client.drain().unwrap_err().to_string().contains("closed"));
        assert!(client.write(b"x", 0).is_err());
        assert!(client.read(1).is_err());
        assert!(client.feed(b"x").is_err());
        client.feed_eof().unwrap();
    }

    #[test]
    fn reads_reuse_one_scratch_buffer() {
        let (mut client, mut server) = pair();
        handshake_in(&mut client, &mut server, usize::MAX).unwrap();
        client.write(b"hello", 0).unwrap();
        deliver(&mut client, &mut server);
        assert_eq!(server.read(2).unwrap(), Outcome::Data(2));
        assert_eq!(server.scratch.len(), MAX_READ);
        assert_eq!(server.read(100).unwrap(), Outcome::Data(3));
        assert_eq!(server.scratch.len(), MAX_READ);
    }
}
