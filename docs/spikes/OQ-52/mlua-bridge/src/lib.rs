//! OQ-52 spike: `serde_json::to_string(&LuaValue)` as `mlua` (feature `serialize`) provides it, with no
//! code of ours. `plain` uses the default options, `tuned` the options closest to the codec's rules.

use mlua::prelude::*;

fn plain(_: &Lua, value: LuaValue) -> LuaResult<Option<String>> {
    Ok(serde_json::to_string(&value).ok())
}

fn tuned(_: &Lua, value: LuaValue) -> LuaResult<Option<String>> {
    let serializable = value
        .to_serializable()
        .deny_unsupported_types(true)
        .deny_recursive_tables(true)
        .detect_mixed_tables(true);
    Ok(serde_json::to_string(&serializable).ok())
}

#[mlua::lua_module(name = "bridge")]
fn module(lua: &Lua) -> LuaResult<LuaTable> {
    let t = lua.create_table()?;
    t.set("plain", lua.create_function(plain)?)?;
    t.set("tuned", lua.create_function(tuned)?)?;
    Ok(t)
}
