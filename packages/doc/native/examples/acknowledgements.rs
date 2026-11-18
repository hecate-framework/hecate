//! Prints the licence texts that two-face embeds for its syntax definitions, for `lua tools/run.lua
//! gen-rust-licences` (ADR 0022). The crate offers them through `two_face::acknowledgement::listing()` only (its
//! `acknowledgements_full.md` is a page of its repository, not a file of the crate). It uses crates the module
//! already depends on: no new dependency.
//!
//! Output, repeated for each licence file: `LICENCE <type> <path> <bytes>`, a newline, that many bytes of text,
//! a newline. Line endings of the text are LF, so that the count is the same through a Windows pipe.

use two_face::acknowledgement::listing;

fn main() {
    for licence in listing().for_syntaxes() {
        let text = licence.text.replace("\r\n", "\n");
        println!(
            "LICENCE {:?} {} {}\n{}",
            licence.ty,
            licence.rel_path.display(),
            text.len(),
            text
        );
    }
}
