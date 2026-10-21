//! Markdown and syntax highlighting for `hecate.doc` (ADR 0022): `comrak` renders GitHub
//! Flavoured Markdown and `syntect` with the `two-face` syntax set highlights code, both bound to
//! Lua 5.5 through `mlua`.
//!
//! Rendering is always in safe mode: raw HTML in the source is replaced by a comment, and
//! `javascript:`, `vbscript:` and `data:` links are dropped (comrak default). Highlighted code is
//! emitted as `<span class="hl-...">` elements, never as inline styles; the site stylesheet maps
//! the scope families to the brand tokens in light and dark.

use comrak::nodes::NodeValue;
use comrak::{parse_document, Arena, Options};
use mlua::prelude::*;
use syntect::html::{ClassStyle, ClassedHTMLGenerator};
use syntect::parsing::SyntaxSet;
use syntect::util::LinesWithEndings;

/// Class prefix of every highlighted token.
const CLASS_PREFIX: &str = "hl-";

fn options() -> Options<'static> {
    let mut options = Options::default();
    options.extension.table = true;
    options.extension.tasklist = true;
    options.extension.strikethrough = true;
    options.extension.autolink = true;
    options.extension.footnotes = true;
    options.extension.alerts = true;
    options.extension.header_id_prefix = Some(String::new());
    options
}

/// One heading of a document, in source order.
#[derive(Debug, PartialEq, Eq)]
pub struct Heading {
    pub level: u8,
    pub text: String,
}

/// The result of rendering one document.
#[derive(Debug)]
pub struct Rendered {
    pub html: String,
    pub headings: Vec<Heading>,
    pub links: Vec<String>,
}

fn text_of<'a>(node: &'a comrak::nodes::AstNode<'a>, out: &mut String) {
    match &node.data.borrow().value {
        NodeValue::Text(t) => out.push_str(t),
        NodeValue::Code(c) => out.push_str(&c.literal),
        NodeValue::SoftBreak | NodeValue::LineBreak => out.push(' '),
        _ => {}
    }
    for child in node.children() {
        text_of(child, out);
    }
}

/// Renders GFM to HTML and collects the headings and the link destinations.
pub fn render(markdown: &str) -> Rendered {
    let options = options();
    let arena = Arena::new();
    let root = parse_document(&arena, markdown, &options);
    let mut headings = Vec::new();
    let mut links = Vec::new();
    for node in root.descendants() {
        match &node.data.borrow().value {
            NodeValue::Heading(h) => {
                let mut text = String::new();
                for child in node.children() {
                    text_of(child, &mut text);
                }
                headings.push(Heading {
                    level: h.level,
                    text,
                });
            }
            NodeValue::Link(l) => links.push(l.url.clone()),
            _ => {}
        }
    }
    let mut html = String::new();
    // Writing to a `String` cannot fail.
    comrak::format_html(root, &options, &mut html).expect("formatting into a String");
    Rendered {
        html,
        headings,
        links,
    }
}

fn syntaxes() -> &'static SyntaxSet {
    use std::sync::OnceLock;
    static SET: OnceLock<SyntaxSet> = OnceLock::new();
    SET.get_or_init(two_face::syntax::extra_newlines)
}

/// Highlights `code` as the language `lang` (a token or an extension), returning the HTML of the
/// spans only, or `None` when the language is unknown.
pub fn highlight(code: &str, lang: &str) -> Option<String> {
    let set = syntaxes();
    let syntax = set.find_syntax_by_token(lang)?;
    let mut generator = ClassedHTMLGenerator::new_with_class_style(
        syntax,
        set,
        ClassStyle::SpacedPrefixed {
            prefix: CLASS_PREFIX,
        },
    );
    for line in LinesWithEndings::from(code) {
        generator
            .parse_html_for_line_which_includes_newline(line)
            .ok()?;
    }
    Some(generator.finalize())
}

#[mlua::lua_module(name = "hecate_doc_native")]
fn module(lua: &Lua) -> LuaResult<LuaTable> {
    let exports = lua.create_table()?;
    exports.set(
        "render",
        lua.create_function(|lua, markdown: LuaString| {
            let markdown = markdown.to_str()?;
            let rendered = render(&markdown);
            let result = lua.create_table()?;
            result.set("html", rendered.html)?;
            let headings = lua.create_table()?;
            for (i, h) in rendered.headings.into_iter().enumerate() {
                let entry = lua.create_table()?;
                entry.set("level", h.level)?;
                entry.set("text", h.text)?;
                headings.set(i + 1, entry)?;
            }
            result.set("headings", headings)?;
            result.set("links", rendered.links)?;
            Ok(result)
        })?,
    )?;
    exports.set(
        "highlight",
        lua.create_function(|_, (code, lang): (LuaString, LuaString)| {
            Ok(highlight(&code.to_str()?, &lang.to_str()?))
        })?,
    )?;
    Ok(exports)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn renders_gfm_extensions() {
        let r = render("# Title\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n- [x] done\n\n~~gone~~ [l](https://e.org)\n");
        assert!(r.html.contains("<table>"));
        assert!(r.html.contains("type=\"checkbox\""));
        assert!(r.html.contains("<del>gone</del>"));
        assert_eq!(
            r.headings,
            vec![Heading {
                level: 1,
                text: "Title".into()
            }]
        );
        assert_eq!(r.links, vec!["https://e.org".to_string()]);
    }

    #[test]
    fn alerts_become_callouts() {
        assert!(render("> [!NOTE]\n> hi\n")
            .html
            .contains("markdown-alert-note"));
    }

    #[test]
    fn raw_html_and_script_links_are_not_passed_through() {
        let r = render("<script>x</script>\n\n[a](javascript:alert(1))\n");
        assert!(!r.html.contains("<script>"));
        assert!(!r.html.contains("javascript:"));
    }

    #[test]
    fn headings_get_ids() {
        assert!(render("## Hello World\n")
            .html
            .contains("id=\"hello-world\""));
    }

    #[test]
    fn highlights_with_prefixed_classes() {
        let html = highlight("local x = 1\n", "lua").expect("lua is known");
        assert!(html.contains("class=\"hl-"), "{html}");
        assert!(!html.contains("style="));
    }

    #[test]
    fn unknown_language_is_none() {
        assert!(highlight("x", "no-such-language").is_none());
    }
}
