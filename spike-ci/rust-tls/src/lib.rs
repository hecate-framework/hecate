// Throwaway OQ-4 spike: sans-IO rustls (no sockets: the caller moves bytes) exposed to Lua 5.5.
use mlua::prelude::*;
use rustls::pki_types::{PrivateKeyDer, ServerName};
use rustls::{ClientConfig, ClientConnection, RootCertStore, ServerConfig, ServerConnection};
use std::io::{Read, Write};
use std::sync::Arc;

fn pump(a: &mut rustls::Connection, b: &mut rustls::Connection) -> usize {
    let mut moved = 0;
    let mut buf = Vec::new();
    while a.wants_write() { a.write_tls(&mut buf).unwrap(); }
    if !buf.is_empty() { moved += buf.len(); let mut s = &buf[..]; while !s.is_empty() { b.read_tls(&mut s).unwrap(); b.process_new_packets().unwrap(); } }
    moved
}

/// selftest(payload) -> echoed payload, rounds: in-memory client/server handshake and one round trip.
fn selftest(_: &Lua, payload: String) -> LuaResult<(String, usize)> {
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    let ck = rcgen::generate_simple_self_signed(vec!["localhost".to_string()]).map_err(LuaError::external)?;
    let cert = ck.cert.der().clone();
    let key = PrivateKeyDer::Pkcs8(ck.key_pair.serialize_der().into());
    let scfg = ServerConfig::builder_with_provider(provider.clone()).with_safe_default_protocol_versions()
        .map_err(LuaError::external)?.with_no_client_auth().with_single_cert(vec![cert.clone()], key).map_err(LuaError::external)?;
    let mut roots = RootCertStore::empty(); roots.add(cert).map_err(LuaError::external)?;
    let ccfg = ClientConfig::builder_with_provider(provider).with_safe_default_protocol_versions()
        .map_err(LuaError::external)?.with_root_certificates(roots).with_no_client_auth();
    let mut c: rustls::Connection = ClientConnection::new(Arc::new(ccfg), ServerName::try_from("localhost").unwrap()).map_err(LuaError::external)?.into();
    let mut s: rustls::Connection = ServerConnection::new(Arc::new(scfg)).map_err(LuaError::external)?.into();
    let mut rounds = 0;
    while c.is_handshaking() || s.is_handshaking() {
        let n = pump(&mut c, &mut s) + pump(&mut s, &mut c);
        rounds += 1;
        if n == 0 || rounds > 20 { return Err(LuaError::external("handshake stalled")); }
    }
    c.writer().write_all(payload.as_bytes()).unwrap();
    pump(&mut c, &mut s);
    let mut out = vec![0u8; payload.len()];
    s.reader().read_exact(&mut out).unwrap();
    Ok((String::from_utf8_lossy(&out).into_owned(), rounds))
}

#[mlua::lua_module]
fn hecate_tls(lua: &Lua) -> LuaResult<LuaTable> {
    let t = lua.create_table()?;
    t.set("selftest", lua.create_function(selftest)?)?;
    Ok(t)
}
