//! Prints the licence texts that two-face embeds for its syntax definitions, for `lua tools/run.lua
//! gen-rust-licences` (ADR 0022). The crate offers them through `two_face::acknowledgement::listing()` only (its
//! `acknowledgements_full.md` is a page of its repository, not a file of the crate). It uses crates the module
//! already depends on: no new dependency.
//!
//! Output, repeated for each licence file: `LICENCE <type> <path> <bytes>`, a newline, that many bytes of text,
//! a newline. Line endings of the text are LF, so that the count is the same through a Windows pipe, and the
//! path separator is `/` on every platform.

use std::io::{self, Write};

use two_face::acknowledgement::listing;

fn main() {
    if let Err(error) = print() {
        eprintln!("acknowledgements: cannot write the output: {error}");
        std::process::exit(1);
    }
}

fn print() -> io::Result<()> {
    let mut out = io::stdout().lock();
    for licence in listing().for_syntaxes() {
        let text = licence.text.replace("\r\n", "\n");
        let path = licence.rel_path.display().to_string().replace('\\', "/");
        writeln!(
            out,
            "LICENCE {:?} {} {}\n{}",
            licence.ty,
            path,
            text.len(),
            text
        )?;
    }
    out.flush()
}
