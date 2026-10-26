//! Markdown and syntax highlighting for `hecate.doc` (ADR 0022): `comrak` renders GitHub
//! Flavoured Markdown and `syntect` with the `two-face` syntax set highlights code, both bound to
//! Lua 5.5 through `mlua`.
//!
//! Rendering is always in safe mode: raw HTML in the source is replaced by a comment, and
//! `javascript:`, `vbscript:` and `data:` links are dropped (comrak default). Highlighted code is
//! emitted as `<span class="hl-...">` elements, never as inline styles; the site stylesheet maps
//! the scope families to the brand tokens in light and dark.
//!
//! Besides the HTML, a render returns what the site model needs: the outline (headings with
//! their identifiers), the plain text of each `##` and `###` section (for search), the title when
//! a leading level-1 heading is stripped, and every link destination.

use std::borrow::Cow;
use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::fmt;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::OnceLock;

use comrak::adapters::{HeadingAdapter, HeadingMeta, SyntaxHighlighterAdapter};
use comrak::nodes::{AlertType, Ast, AstNode, NodeValue, Sourcepos};
use comrak::options::Plugins;
use comrak::{format_html_with_plugins, parse_document, Arena, Options};
use mlua::prelude::*;
use syntect::html::{ClassStyle, ClassedHTMLGenerator};
use syntect::parsing::SyntaxSet;
use syntect::util::LinesWithEndings;

/// Class prefix of every highlighted token.
const CLASS_PREFIX: &str = "hl-";

/// One heading of a document, in source order.
#[derive(Debug, PartialEq, Eq)]
pub struct Heading {
    pub level: u8,
    pub id: String,
    pub text: String,
}

/// The text of the document between two `##` or `###` headings (the first section has no heading).
#[derive(Debug, PartialEq, Eq)]
pub struct Section {
    pub id: Option<String>,
    pub heading: Option<String>,
    pub level: Option<u8>,
    pub text: String,
}

/// How a document is rendered.
pub struct Config {
    /// Titles of the callouts that have none of their own: note, tip, warning, danger (the GFM `CAUTION` alert), important.
    pub labels: [Option<String>; 5],
    /// Remove a leading level-1 heading and return its text as the title.
    pub strip_title: bool,
    /// Add a permalink to every heading.
    pub heading_anchors: bool,
    /// Highlight fenced code.
    pub highlight: bool,
}

impl Default for Config {
    fn default() -> Self {
        Config {
            labels: Default::default(),
            strip_title: false,
            heading_anchors: true,
            highlight: true,
        }
    }
}

/// The result of rendering one document.
#[derive(Debug)]
pub struct Rendered {
    pub html: String,
    pub title: Option<String>,
    pub headings: Vec<Heading>,
    pub sections: Vec<Section>,
    /// Every link and image destination met, as written, in document order.
    pub links: Vec<String>,
}

fn escape(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for c in text.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&#39;"),
            _ => out.push(c),
        }
    }
    out
}

fn text_of<'a>(node: &'a AstNode<'a>, out: &mut String) {
    match &node.data.borrow().value {
        NodeValue::Text(t) => out.push_str(t),
        NodeValue::Code(c) => out.push_str(&c.literal),
        NodeValue::CodeBlock(c) => out.push_str(&c.literal),
        NodeValue::SoftBreak | NodeValue::LineBreak => out.push(' '),
        _ => {}
    }
    for child in node.children() {
        text_of(child, out);
    }
}

fn plain<'a>(node: &'a AstNode<'a>) -> String {
    let mut out = String::new();
    text_of(node, &mut out);
    out
}

/// A heading identifier: lower case, spaces become hyphens, ASCII punctuation is dropped except
/// `-` and `_`, non-ASCII letters are kept.
fn slug(text: &str) -> String {
    let mut out = String::new();
    for c in text.chars().flat_map(char::to_lowercase) {
        if c.is_control() {
            continue;
        }
        if c.is_whitespace() {
            out.push('-');
        } else if c == '-' || c == '_' || !c.is_ascii_punctuation() {
            out.push(c);
        }
    }
    let mut collapsed = String::new();
    for c in out.chars() {
        if !(c == '-' && collapsed.ends_with('-')) {
            collapsed.push(c);
        }
    }
    let trimmed = collapsed.trim_matches('-');
    if trimmed.is_empty() {
        "section".to_string()
    } else {
        trimmed.to_string()
    }
}

/// Splits a trailing custom identifier `{#id}` off the text of a heading.
fn custom_id(text: &str) -> Option<(&str, &str)> {
    let body = text.trim_end().strip_suffix('}')?;
    let at = body.rfind("{#")?;
    let id = &body[at + 2..];
    if id.is_empty()
        || !id
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || "_-.:".contains(c))
    {
        return None;
    }
    Some((body[..at].trim_end(), id))
}

fn unique(taken: &mut HashSet<String>, base: &str) -> String {
    let mut id = base.to_string();
    let mut suffix = 0;
    while taken.contains(&id) {
        suffix += 1;
        id = format!("{base}-{suffix}");
    }
    taken.insert(id.clone());
    id
}

/// The language of a code block: the first word of the info string, when it is a plain name.
fn language_of(info: &str) -> Option<String> {
    let word = info
        .split(|c: char| c.is_whitespace() || c == '{')
        .next()
        .unwrap_or("");
    let plain = !word.is_empty()
        && word
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || "_+#.-".contains(c));
    plain.then(|| word.to_string())
}

struct Headings {
    entries: Vec<(String, String)>,
    next: AtomicUsize,
    anchors: bool,
}

impl HeadingAdapter for Headings {
    fn enter(
        &self,
        output: &mut dyn fmt::Write,
        heading: &HeadingMeta,
        _: Option<Sourcepos>,
    ) -> fmt::Result {
        let id = self
            .entries
            .get(self.next.load(Ordering::Relaxed))
            .map_or("", |e| e.0.as_str());
        write!(
            output,
            "<h{} id=\"{}\" tabindex=\"-1\">",
            heading.level,
            escape(id)
        )
    }

    fn exit(&self, output: &mut dyn fmt::Write, heading: &HeadingMeta) -> fmt::Result {
        let i = self.next.fetch_add(1, Ordering::Relaxed);
        if let (true, Some((id, text))) = (self.anchors, self.entries.get(i)) {
            write!(
                output,
                "<a class=\"header-anchor\" href=\"#{}\" aria-label=\"Permalink to \u{201c}{}\u{201d}\"></a>",
                escape(id),
                escape(text)
            )?;
        }
        write!(output, "</h{}>", heading.level)
    }
}

/// Wraps code blocks in the toolbar markup of the theme. `comrak` calls the three methods once
/// per code block, in document order, so the languages found before rendering are consumed in order.
struct Code {
    languages: Vec<Option<String>>,
    next: AtomicUsize,
    highlight: bool,
}

impl Code {
    fn language(&self) -> Option<&str> {
        self.languages
            .get(self.next.load(Ordering::Relaxed))
            .and_then(|l| l.as_deref())
    }
}

impl SyntaxHighlighterAdapter for Code {
    fn write_highlighted(
        &self,
        output: &mut dyn fmt::Write,
        _: Option<&str>,
        code: &str,
    ) -> fmt::Result {
        let html = self
            .language()
            .filter(|_| self.highlight)
            .and_then(|l| highlight(code, l));
        self.next.fetch_add(1, Ordering::Relaxed);
        output.write_str(&html.unwrap_or_else(|| escape(code)))
    }

    fn write_pre_tag(
        &self,
        output: &mut dyn fmt::Write,
        _: HashMap<&'static str, Cow<'_, str>>,
    ) -> fmt::Result {
        match self.language() {
            Some(language) => {
                let label = syntaxes()
                    .find_syntax_by_token(language)
                    .map_or(language, |s| s.name.as_str());
                write!(
                    output,
                    "<div class=\"code-block\" data-language=\"{}\"><div class=\"code-toolbar\"><span class=\"code-language\">{}</span></div><pre tabindex=\"0\">",
                    escape(&language.to_lowercase()),
                    escape(label)
                )
            }
            None => output.write_str(
                "<div class=\"code-block\"><div class=\"code-toolbar\"></div><pre tabindex=\"0\">",
            ),
        }
    }

    fn write_code_tag(
        &self,
        output: &mut dyn fmt::Write,
        _: HashMap<&'static str, Cow<'_, str>>,
    ) -> fmt::Result {
        match self.language() {
            Some(language) => write!(
                output,
                "<code class=\"language-{}\">",
                escape(&language.to_lowercase())
            ),
            None => output.write_str("<code>"),
        }
    }
}

fn options() -> Options<'static> {
    let mut options = Options::default();
    options.extension.table = true;
    options.extension.tasklist = true;
    options.extension.strikethrough = true;
    options.extension.autolink = true;
    options.extension.footnotes = true;
    options.extension.alerts = true;
    options.render.tasklist_classes = true;
    options
}

/// Renders GFM to HTML. `resolve` rewrites every link and image destination (site links).
///
/// # Errors
///
/// The first error returned by `resolve`.
pub fn render(
    markdown: &str,
    config: &Config,
    resolve: &mut dyn FnMut(&str) -> Result<String, String>,
) -> Result<Rendered, String> {
    let options = options();
    let arena = Arena::new();
    let root = parse_document(&arena, markdown, &options);

    // Raw HTML is shown as text, never passed through; comments are dropped so that generated
    // pages can carry their "generated, do not edit" header.
    let raw: Vec<_> = root
        .descendants()
        .filter(|n| {
            matches!(
                n.data.borrow().value,
                NodeValue::HtmlBlock(_) | NodeValue::HtmlInline(_)
            )
        })
        .collect();
    for node in raw {
        let (literal, block) = match &node.data.borrow().value {
            NodeValue::HtmlBlock(b) => (b.literal.clone(), true),
            NodeValue::HtmlInline(l) => (l.clone(), false),
            _ => continue,
        };
        let trimmed = literal.trim();
        if trimmed.starts_with("<!--") && trimmed.ends_with("-->") {
            node.detach();
        } else if block {
            let text = arena.alloc(AstNode::new(RefCell::new(Ast::new(
                NodeValue::Text(trimmed.to_string().into()),
                (0, 0).into(),
            ))));
            node.data.borrow_mut().value = NodeValue::Paragraph;
            node.append(text);
        } else {
            node.data.borrow_mut().value = NodeValue::Text(literal.into());
        }
    }

    // Destinations, in document order.
    let mut links = Vec::new();
    for node in root.descendants() {
        let mut data = node.data.borrow_mut();
        match &mut data.value {
            NodeValue::Link(l) | NodeValue::Image(l) => {
                links.push(l.url.clone());
                l.url = resolve(&l.url)?;
            }
            NodeValue::Alert(a) if a.title.is_none() => {
                let slot = match a.alert_type {
                    AlertType::Note => 0,
                    AlertType::Tip => 1,
                    AlertType::Warning => 2,
                    AlertType::Caution => 3,
                    AlertType::Important => 4,
                };
                a.title = config.labels[slot].clone();
            }
            _ => {}
        }
    }

    // A leading level-1 heading is the title of the page, not part of its body.
    let mut title = None;
    if config.strip_title {
        if let Some(first) = root.first_child() {
            if matches!(first.data.borrow().value, NodeValue::Heading(ref h) if h.level == 1) {
                let text = plain(first);
                title = Some(custom_id(&text).map_or(text.clone(), |(t, _)| t.to_string()));
                first.detach();
            }
        }
    }

    // Headings: strip `{#custom}` ids from their text, then number them.
    let mut taken = HashSet::new();
    let mut headings = Vec::new();
    for node in root.descendants() {
        let level = match node.data.borrow().value {
            NodeValue::Heading(ref h) => h.level,
            _ => continue,
        };
        let mut custom = None;
        if let Some(last) = node.last_child() {
            let mut data = last.data.borrow_mut();
            if let NodeValue::Text(ref mut t) = data.value {
                if let Some((rest, id)) = custom_id(t) {
                    custom = Some(id.to_string());
                    *t = rest.to_string().into();
                }
            }
        }
        let text = plain(node);
        let id = unique(&mut taken, &custom.unwrap_or_else(|| slug(&text)));
        headings.push(Heading { level, id, text });
    }

    // Sections for search: the plain text of each top-level block, split at `##` and `###`.
    let mut sections = vec![Section {
        id: None,
        heading: None,
        level: None,
        text: String::new(),
    }];
    let mut heading_index = 0;
    for block in root.children() {
        let is_heading = matches!(block.data.borrow().value, NodeValue::Heading(_));
        if is_heading {
            let heading = &headings[heading_index];
            heading_index += 1;
            if heading.level == 2 || heading.level == 3 {
                sections.push(Section {
                    id: Some(heading.id.clone()),
                    heading: Some(heading.text.clone()),
                    level: Some(heading.level),
                    text: String::new(),
                });
                continue;
            }
        } else {
            // Headings nested in containers (quotes, lists) are numbered too; skip their ids here.
            heading_index += block
                .descendants()
                .skip(1)
                .filter(|n| matches!(n.data.borrow().value, NodeValue::Heading(_)))
                .count();
        }
        let current = sections.last_mut().expect("one section at least");
        current.text.push(' ');
        current.text.push_str(&plain(block));
    }
    for section in &mut sections {
        section.text = section
            .text
            .split_whitespace()
            .collect::<Vec<_>>()
            .join(" ");
    }

    // Code blocks, in document order.
    let languages: Vec<Option<String>> = root
        .descendants()
        .filter_map(|n| match n.data.borrow().value {
            NodeValue::CodeBlock(ref c) => Some(if c.fenced { language_of(&c.info) } else { None }),
            _ => None,
        })
        .collect();

    let heading_adapter = Headings {
        entries: headings
            .iter()
            .map(|h| (h.id.clone(), h.text.clone()))
            .collect(),
        next: AtomicUsize::new(0),
        anchors: config.heading_anchors,
    };
    let code_adapter = Code {
        languages,
        next: AtomicUsize::new(0),
        highlight: config.highlight,
    };
    let mut plugins = Plugins::default();
    plugins.render.heading_adapter = Some(&heading_adapter);
    plugins.render.codefence_syntax_highlighter = Some(&code_adapter);
    let mut html = String::new();
    format_html_with_plugins(root, &options, &mut html, &plugins).map_err(|e| e.to_string())?;
    let html = html.replace("</code></pre>", "</code></pre></div>");
    Ok(Rendered {
        html,
        title,
        headings,
        sections,
        links,
    })
}

fn syntaxes() -> &'static SyntaxSet {
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

fn config_from(options: Option<LuaTable>) -> LuaResult<(Config, Option<LuaFunction>)> {
    let mut config = Config::default();
    let Some(options) = options else {
        return Ok((config, None));
    };
    if let Some(labels) = options.get::<Option<LuaTable>>("labels")? {
        for (slot, name) in ["note", "tip", "warning", "danger", "important"]
            .into_iter()
            .enumerate()
        {
            config.labels[slot] = labels.get::<Option<String>>(name)?;
        }
    }
    config.strip_title = options.get::<Option<bool>>("strip_title")?.unwrap_or(false);
    config.heading_anchors = options
        .get::<Option<bool>>("heading_anchors")?
        .unwrap_or(true);
    config.highlight = options.get::<Option<bool>>("highlight")?.unwrap_or(true);
    Ok((config, options.get::<Option<LuaFunction>>("resolve_link")?))
}

fn rendered_to_lua(lua: &Lua, rendered: Rendered) -> LuaResult<LuaTable> {
    let result = lua.create_table()?;
    result.set("html", rendered.html)?;
    result.set("title", rendered.title)?;
    let headings = lua.create_table()?;
    for (i, h) in rendered.headings.into_iter().enumerate() {
        let entry = lua.create_table()?;
        entry.set("level", h.level)?;
        entry.set("id", h.id)?;
        entry.set("text", h.text)?;
        headings.set(i + 1, entry)?;
    }
    result.set("headings", headings)?;
    let sections = lua.create_table()?;
    for (i, s) in rendered.sections.into_iter().enumerate() {
        let entry = lua.create_table()?;
        entry.set("id", s.id)?;
        entry.set("heading", s.heading)?;
        entry.set("level", s.level)?;
        entry.set("text", s.text)?;
        sections.set(i + 1, entry)?;
    }
    result.set("sections", sections)?;
    result.set("links", rendered.links)?;
    Ok(result)
}

/// Renders with the options of the specifications: raw HTML kept and, when `extension` names one of the
/// GFM extensions of the specification (`table`, `strikethrough`, `autolink`), that
/// extension only; none by default (CommonMark). It exists so that the specification examples can
/// run through this module (OQ-37); the site never uses it.
pub fn commonmark(markdown: &str, extension: Option<&str>) -> String {
    let mut options = Options::default();
    options.render.r#unsafe = true;
    match extension {
        Some("table") => options.extension.table = true,
        Some("strikethrough") => options.extension.strikethrough = true,
        Some("autolink") => options.extension.autolink = true,
        _ => {}
    }
    comrak::markdown_to_html(markdown, &options)
}

#[mlua::lua_module(name = "hecate_doc_native")]
fn module(lua: &Lua) -> LuaResult<LuaTable> {
    let exports = lua.create_table()?;
    exports.set(
        "render",
        lua.create_function(|lua, (markdown, options): (LuaString, Option<LuaTable>)| {
            let markdown = markdown.to_str()?;
            let (config, resolve) = config_from(options)?;
            let mut failure: Option<LuaError> = None;
            let rendered = render(&markdown, &config, &mut |href| match &resolve {
                None => Ok(href.to_string()),
                Some(f) => f.call::<String>(href).map_err(|e| {
                    failure = Some(e);
                    String::new()
                }),
            });
            match rendered {
                Ok(rendered) => rendered_to_lua(lua, rendered),
                Err(message) => Err(failure.unwrap_or_else(|| LuaError::runtime(message))),
            }
        })?,
    )?;
    exports.set(
        "commonmark",
        lua.create_function(|_, (markdown, extension): (LuaString, Option<LuaString>)| {
            let extension = extension
                .map(|e| e.to_str().map(|e| e.to_string()))
                .transpose()?;
            Ok(commonmark(&markdown.to_str()?, extension.as_deref()))
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

    fn run(markdown: &str) -> Rendered {
        render(markdown, &Config::default(), &mut |h| Ok(h.to_string())).expect("renders")
    }

    #[test]
    fn renders_gfm_extensions() {
        let r = run("# Title\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n- [x] done\n\n~~gone~~ [l](https://e.org)\n");
        assert!(r.html.contains("<table>"));
        assert!(r.html.contains("type=\"checkbox\""));
        assert!(r.html.contains("<del>gone</del>"));
        assert_eq!(
            r.headings,
            vec![Heading {
                level: 1,
                id: "title".into(),
                text: "Title".into()
            }]
        );
        assert_eq!(r.links, vec!["https://e.org".to_string()]);
    }

    #[test]
    fn alerts_become_callouts_with_the_configured_title() {
        let mut config = Config::default();
        config.labels[0] = Some("Remarque".into());
        let r = render("> [!NOTE]\n> hi\n", &config, &mut |h| Ok(h.to_string())).expect("renders");
        assert!(r.html.contains("markdown-alert-note"));
        assert!(r.html.contains("Remarque"));
    }

    #[test]
    fn raw_html_and_script_links_are_not_passed_through() {
        let r = run("<script>x</script>\n\n[a](javascript:alert(1))\n");
        assert!(!r.html.contains("<script>"));
        assert!(!r.html.contains("javascript:"));
    }

    #[test]
    fn headings_get_unique_ids_anchors_and_custom_ids() {
        let r = run("## Hello World\n\n## Hello World\n\n## Custom {#mine}\n");
        let ids: Vec<_> = r.headings.iter().map(|h| h.id.as_str()).collect();
        assert_eq!(ids, ["hello-world", "hello-world-1", "mine"]);
        assert_eq!(r.headings[2].text, "Custom");
        assert!(r.html.contains("<h2 id=\"hello-world-1\" tabindex=\"-1\">Hello World<a class=\"header-anchor\" href=\"#hello-world-1\""));
        assert!(!r.html.contains("{#mine}"));
    }

    #[test]
    fn a_leading_title_is_stripped() {
        let config = Config {
            strip_title: true,
            ..Config::default()
        };
        let r = render(
            "# Page title\n\nBody\n\n## Part\n\nMore\n",
            &config,
            &mut |h| Ok(h.to_string()),
        )
        .expect("renders");
        assert_eq!(r.title.as_deref(), Some("Page title"));
        assert!(!r.html.contains("Page title"));
        assert_eq!(r.headings.len(), 1);
        assert_eq!(r.sections[0].text, "Body");
        assert_eq!(r.sections[1].heading.as_deref(), Some("Part"));
        assert_eq!(r.sections[1].text, "More");
    }

    #[test]
    fn links_and_images_are_rewritten() {
        let r = render("[a](x.md) ![b](y.png)", &Config::default(), &mut |h| {
            Ok(format!("/base/{h}"))
        })
        .expect("renders");
        assert!(r.html.contains("href=\"/base/x.md\""));
        assert!(r.html.contains("src=\"/base/y.png\""));
        assert_eq!(r.links, vec!["x.md".to_string(), "y.png".to_string()]);
    }

    #[test]
    fn code_blocks_are_wrapped_and_highlighted() {
        let r = run("```lua\nlocal x = 1\n```\n\n    indented\n\n```\nplain\n```\n");
        assert!(
            r.html
                .contains("<div class=\"code-block\" data-language=\"lua\">"),
            "{}",
            r.html
        );
        assert!(
            r.html.contains("<span class=\"code-language\">Lua</span>"),
            "{}",
            r.html
        );
        assert!(
            r.html
                .contains("<code class=\"language-lua\"><span class=\"hl-"),
            "{}",
            r.html
        );
        assert_eq!(r.html.matches("<div class=\"code-block\"").count(), 3);
        assert_eq!(r.html.matches("</pre></div>").count(), 3);
        assert!(!r.html.contains("style="));
    }

    #[test]
    fn highlighting_can_be_turned_off() {
        let config = Config {
            highlight: false,
            ..Config::default()
        };
        let r = render("```lua\nlocal x <const> = 1\n```\n", &config, &mut |h| {
            Ok(h.to_string())
        })
        .expect("renders");
        assert!(r.html.contains("local x &lt;const&gt; = 1"));
        assert!(!r.html.contains("hl-"));
    }

    #[test]
    fn unknown_language_is_none() {
        assert!(highlight("x", "no-such-language").is_none());
    }
}
