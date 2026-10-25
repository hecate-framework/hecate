// The library links mlua with the `module` feature: the Lua symbols are resolved by the interpreter
// that loads the module. The fuzz entry points never call into Lua, so a standalone binary may leave
// them unresolved.
fn main() {
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("linux") {
        println!("cargo:rustc-link-arg-bins=-Wl,--unresolved-symbols=ignore-all");
    }
}
