// The library links mlua with the `module` feature: the Lua symbols are normally resolved by the
// interpreter that loads the module. A standalone fuzz binary needs them at start-up, so it links the
// Lua library of the toolchain: LUA_LIB is its directory, LUA_LIB_NAME its name (default `lua`) and
// LUA_LIB_KIND `static` (default) or `dylib`.
fn main() {
    println!("cargo:rerun-if-env-changed=LUA_LIB");
    println!("cargo:rerun-if-env-changed=LUA_LIB_NAME");
    println!("cargo:rerun-if-env-changed=LUA_LIB_KIND");
    let Ok(dir) = std::env::var("LUA_LIB") else {
        panic!("set LUA_LIB to the directory of the Lua library (liblua.a), for example .hecate/toolchain/lib");
    };
    let name = std::env::var("LUA_LIB_NAME").unwrap_or_else(|_| "lua".to_string());
    let kind = std::env::var("LUA_LIB_KIND").unwrap_or_else(|_| "static".to_string());
    println!("cargo:rustc-link-search=native={dir}");
    println!("cargo:rustc-link-lib={kind}={name}");
    if std::env::var("CARGO_CFG_TARGET_FAMILY").as_deref() == Ok("unix") {
        println!("cargo:rustc-link-lib=m");
        println!("cargo:rustc-link-lib=dl");
    }
}
