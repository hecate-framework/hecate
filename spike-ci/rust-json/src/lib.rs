// Throwaway OQ-5 spike: Rust JSON codecs exposed to Lua 5.5 through mlua's serde bridge.
use mlua::prelude::*;

fn serde_decode(lua: &Lua, s: mlua::String) -> LuaResult<LuaValue> {
    let v: serde_json::Value = serde_json::from_slice(&s.as_bytes()).map_err(LuaError::external)?;
    lua.to_value(&v)
}
fn sonic_decode(lua: &Lua, s: mlua::String) -> LuaResult<LuaValue> {
    let v: sonic_rs::Value = sonic_rs::from_slice(&s.as_bytes()).map_err(LuaError::external)?;
    lua.to_value(&v)
}
fn simd_decode(lua: &Lua, s: mlua::String) -> LuaResult<LuaValue> {
    let mut b = s.as_bytes().to_vec();
    let v = simd_json::to_owned_value(&mut b).map_err(LuaError::external)?;
    lua.to_value(&v)
}
fn serde_encode(_: &Lua, v: LuaValue) -> LuaResult<String> { serde_json::to_string(&v).map_err(LuaError::external) }
fn sonic_encode(_: &Lua, v: LuaValue) -> LuaResult<String> { sonic_rs::to_string(&v).map_err(LuaError::external) }

fn esc(out: &mut Vec<u8>, b: &[u8]) {
    out.push(b'"');
    for &c in b {
        match c {
            b'"' => out.extend_from_slice(b"\\\""), b'\\' => out.extend_from_slice(b"\\\\"),
            b'\n' => out.extend_from_slice(b"\\n"), b'\r' => out.extend_from_slice(b"\\r"), b'\t' => out.extend_from_slice(b"\\t"),
            0..=0x1f => out.extend_from_slice(format!("\\u{:04x}", c).as_bytes()),
            _ => out.push(c),
        }
    }
    out.push(b'"');
}
fn walk(out: &mut Vec<u8>, v: &LuaValue, depth: usize) -> LuaResult<()> {
    if depth > 1000 { return Err(LuaError::external("nesting too deep")); }
    match v {
        LuaValue::Nil | LuaValue::LightUserData(_) => out.extend_from_slice(b"null"),
        LuaValue::Boolean(b) => out.extend_from_slice(if *b { b"true" } else { b"false" }),
        LuaValue::Integer(i) => out.extend_from_slice(i.to_string().as_bytes()),
        LuaValue::Number(n) => { if !n.is_finite() { return Err(LuaError::external("non-finite number")); } let mut b = ryu_fmt(*n); out.append(&mut b); }
        LuaValue::String(s) => esc(out, &s.as_bytes()),
        LuaValue::Table(t) => {
            let n = t.raw_len();
            if n > 0 {
                out.push(b'[');
                for i in 1..=n { if i > 1 { out.push(b','); } walk(out, &t.raw_get::<LuaValue>(i)?, depth + 1)?; }
                out.push(b']');
            } else {
                out.push(b'{'); let mut first = true;
                for pair in t.pairs::<LuaValue, LuaValue>() {
                    let (k, val) = pair?;
                    let LuaValue::String(k) = k else { return Err(LuaError::external("non-string key")); };
                    if !first { out.push(b','); } first = false;
                    esc(out, &k.as_bytes()); out.push(b':'); walk(out, &val, depth + 1)?;
                }
                out.push(b'}');
            }
        }
        _ => return Err(LuaError::external("unsupported type")),
    }
    Ok(())
}
fn ryu_fmt(n: f64) -> Vec<u8> { let s = format!("{}", n); s.into_bytes() }
fn direct_encode(lua: &Lua, v: LuaValue) -> LuaResult<mlua::String> {
    let mut out = Vec::with_capacity(4096); walk(&mut out, &v, 0)?; lua.create_string(&out)
}

#[mlua::lua_module]
fn hecate_json(lua: &Lua) -> LuaResult<LuaTable> {
    let t = lua.create_table()?;
    t.set("serde_decode", lua.create_function(serde_decode)?)?;
    t.set("sonic_decode", lua.create_function(sonic_decode)?)?;
    t.set("simd_decode", lua.create_function(simd_decode)?)?;
    t.set("serde_encode", lua.create_function(serde_encode)?)?;
    t.set("sonic_encode", lua.create_function(sonic_encode)?)?;
    t.set("direct_encode", lua.create_function(direct_encode)?)?;
    t.set("null", lua.null())?;
    Ok(t)
}
