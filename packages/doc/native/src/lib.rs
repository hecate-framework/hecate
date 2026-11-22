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
use std::collections::{BTreeMap, HashMap, HashSet};
use std::fmt;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::OnceLock;

use comrak::adapters::{
    HeadingAdapter, HeadingMeta, SyntaxHighlightMeta, SyntaxHighlighterAdapter,
};
use comrak::nodes::{AlertType, Ast, AstNode, NodeValue};
use comrak::options::Plugins;
use comrak::{format_html_with_plugins, parse_document, Arena, Options};
use mlua::prelude::*;
use syntect::html::{ClassStyle, ClassedHTMLGenerator};
use syntect::parsing::SyntaxSet;
use syntect::util::LinesWithEndings;

/// The most block containers (`>` quotes and list items) that one line may open, counted by
/// [`check_nesting`] from the leading prefix of the line only. It bounds nothing else: not inline
/// nesting (emphasis, links, images), not the number of lines, not a container opened by a lazy
/// continuation. Comrak parses and formats iteratively, so this is not what keeps the stack safe: it
/// is a documented bound on what one line may ask of the renderer (without it a run of 100000 `>`
/// takes tens of seconds, quadratic in the depth) that stays far above real documentation, which
/// rarely nests beyond five levels. [`MAX_INPUT_BYTES`] and [`MAX_OUTPUT_BYTES`] bound the rest.
pub const MAX_NESTING: usize = 100;

/// The largest Markdown text (or code text) an entry point accepts, in bytes: 8 MiB. A page of
/// documentation is a few tens of kilobytes; the cap keeps the memory and the time of one call
/// bounded.
pub const MAX_INPUT_BYTES: usize = 8 * 1024 * 1024;

/// The largest HTML a render may produce, in bytes: 64 MiB (eight times [`MAX_INPUT_BYTES`]).
pub const MAX_OUTPUT_BYTES: usize = 64 * 1024 * 1024;

/// The HTML of a render may be at most this many times the size of its Markdown (footnote
/// references amplify by about 27, highlighted code by less than 10), but never less than
/// [`OUTPUT_FLOOR_BYTES`] and never more than [`MAX_OUTPUT_BYTES`].
pub const MAX_OUTPUT_RATIO: usize = 32;

/// A render may always produce this much HTML (1 MiB), so that a short page with a lot of markup
/// per character is not refused by the ratio.
pub const OUTPUT_FLOOR_BYTES: usize = 1024 * 1024;

/// The most HTML a render of `input_len` bytes of Markdown may produce.
pub fn output_limit(input_len: usize) -> usize {
    input_len
        .saturating_mul(MAX_OUTPUT_RATIO)
        .clamp(OUTPUT_FLOOR_BYTES, MAX_OUTPUT_BYTES)
}

/// Checks the size of a text received from Lua, then that it is UTF-8.
///
/// # Errors
///
/// A message naming the limit, or the position (1-based, like `utf8.len`) of the first invalid byte.
pub fn check_input<'a>(what: &str, bytes: &'a [u8]) -> Result<&'a str, String> {
    if bytes.len() > MAX_INPUT_BYTES {
        return Err(format!(
            "the {what} is {} bytes, more than the limit of {MAX_INPUT_BYTES} bytes (8 MiB)",
            bytes.len()
        ));
    }
    std::str::from_utf8(bytes).map_err(|e| {
        format!(
            "the {what} is not valid UTF-8 (invalid byte at position {})",
            e.valid_up_to() + 1
        )
    })
}

/// A `fmt::Write` that fails once it would hold more than `limit` bytes, so that an amplifying
/// document is stopped while it renders instead of after it has used the memory.
struct Bounded {
    out: String,
    limit: usize,
    exceeded: bool,
}

impl fmt::Write for Bounded {
    fn write_str(&mut self, s: &str) -> fmt::Result {
        if self.out.len().saturating_add(s.len()) > self.limit {
            self.exceeded = true;
            return Err(fmt::Error);
        }
        self.out.push_str(s);
        Ok(())
    }
}

fn output_refusal(limit: usize) -> String {
    format!(
        "the rendered HTML is larger than {limit} bytes (the limit is {MAX_OUTPUT_RATIO} times the size of the \
         Markdown, between 1 MiB and {MAX_OUTPUT_BYTES} bytes)"
    )
}

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

/// Checks that no line opens more than [`MAX_NESTING`] block containers. The container markers of
/// a line are read from its leading prefix: spaces, `>`, a bullet (`-`, `+`, `*`) followed by a
/// space or tab, or an ordered marker (1 to 9 digits, `.` or `)`, then a space or tab; CommonMark
/// 0.31.2, sections 5.1, 5.2 and 5.3). The scan is conservative: it ignores code fences, so a
/// fenced block that quotes a deeply nested line is refused too.
///
/// # Errors
///
/// A message naming the first offending line (1-based).
pub fn check_nesting(markdown: &str) -> Result<(), String> {
    for (index, line) in markdown.split('\n').enumerate() {
        let bytes = line.as_bytes();
        let (mut at, mut depth) = (0, 0);
        while at < bytes.len() {
            match bytes[at] {
                b' ' | b'\t' | b'\r' => at += 1,
                b'>' => {
                    depth += 1;
                    at += 1;
                }
                b'-' | b'+' | b'*' if matches!(bytes.get(at + 1), Some(b' ' | b'\t')) => {
                    depth += 1;
                    at += 2;
                }
                b'0'..=b'9' => {
                    let digits = bytes[at..]
                        .iter()
                        .take_while(|b| b.is_ascii_digit())
                        .count();
                    let end = at + digits;
                    let marker = matches!(bytes.get(end), Some(b'.' | b')'))
                        && matches!(bytes.get(end + 1), Some(b' ' | b'\t'));
                    if digits > 9 || !marker {
                        break;
                    }
                    depth += 1;
                    at = end + 2;
                }
                _ => break,
            }
            if depth > MAX_NESTING {
                return Err(format!(
                    "line {} nests more than {MAX_NESTING} block containers (quotes and list items)",
                    index + 1
                ));
            }
        }
    }
    Ok(())
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

/// Appends the plain text of `node` and its descendants, in document order. Iterative: a document
/// nests to any depth, and a native stack overflow cannot be caught.
fn text_of<'a>(node: &'a AstNode<'a>, out: &mut String) {
    for node in node.descendants() {
        match &node.data.borrow().value {
            NodeValue::Text(t) => out.push_str(t),
            NodeValue::Code(c) => out.push_str(&c.literal),
            NodeValue::CodeBlock(c) => out.push_str(&c.literal),
            NodeValue::SoftBreak | NodeValue::LineBreak => out.push(' '),
            _ => {}
        }
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

/// The heading identifiers handed out so far. `next` remembers, per base identifier, the last
/// suffix given: every `base-1` to `base-n` is taken, so the search resumes after `n` and a run of
/// identical headings costs amortised O(1) each instead of O(n).
#[derive(Default)]
struct Identifiers {
    taken: HashSet<String>,
    next: HashMap<String, usize>,
}

impl Identifiers {
    fn unique(&mut self, base: &str) -> String {
        if self.taken.insert(base.to_string()) {
            return base.to_string();
        }
        let counter = self.next.entry(base.to_string()).or_insert(0);
        loop {
            *counter += 1;
            let id = format!("{base}-{counter}");
            // A custom identifier (`{#h-1}`) may have taken the candidate already.
            if self.taken.insert(id.clone()) {
                return id;
            }
        }
    }
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
    fn enter(&self, output: &mut dyn fmt::Write, heading: &HeadingMeta) -> fmt::Result {
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
        meta: &SyntaxHighlightMeta<'_>,
    ) -> fmt::Result {
        let code = meta.code;
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
        _: &SyntaxHighlightMeta<'_>,
        _: BTreeMap<&str, Cow<'_, str>>,
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
        _: &SyntaxHighlightMeta<'_>,
        _: BTreeMap<&str, Cow<'_, str>>,
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
/// The first error returned by `resolve`, or a message when the Markdown is larger than
/// [`MAX_INPUT_BYTES`] or the HTML would exceed [`output_limit`].
pub fn render(
    markdown: &str,
    config: &Config,
    resolve: &mut dyn FnMut(&str) -> Result<String, String>,
) -> Result<Rendered, String> {
    check_input("markdown", markdown.as_bytes())?;
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
                // `AlertType` is non-exhaustive in comrak 1.x: a future kind keeps its default title.
                let slot = match a.alert_type {
                    AlertType::Note => Some(0),
                    AlertType::Tip => Some(1),
                    AlertType::Warning => Some(2),
                    AlertType::Caution => Some(3),
                    AlertType::Important => Some(4),
                    _ => None,
                };
                if let Some(slot) = slot {
                    a.title = config.labels[slot].clone();
                }
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
    let mut identifiers = Identifiers::default();
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
        let id = identifiers.unique(&custom.unwrap_or_else(|| slug(&text)));
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
            let heading = headings
                .get(heading_index)
                .ok_or_else(|| "internal: heading count mismatch".to_string())?;
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
        let current = sections
            .last_mut()
            .ok_or_else(|| "internal: heading count mismatch".to_string())?;
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
    let limit = output_limit(markdown.len());
    let mut bounded = Bounded {
        out: String::new(),
        limit,
        exceeded: false,
    };
    if let Err(e) = format_html_with_plugins(root, &options, &mut bounded, &plugins) {
        return Err(if bounded.exceeded {
            output_refusal(limit)
        } else {
            e.to_string()
        });
    }
    let html = bounded.out.replace("</code></pre>", "</code></pre></div>");
    if html.len() > limit {
        return Err(output_refusal(limit));
    }
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
/// run through this module (OQ-37); the site never uses it. This is the unsafe renderer: it is
/// compiled only with the `spec-tests` feature, so the shipped module exposes the safe renderer
/// alone.
#[cfg(feature = "spec-tests")]
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
            // A refusal is `nil, message`; the Lua wrapper raises it as an argument error.
            let bytes = markdown.as_bytes();
            let markdown = match check_input("markdown", &bytes) {
                Ok(text) => text,
                Err(message) => return (LuaNil, message).into_lua_multi(lua),
            };
            if let Err(message) = check_nesting(markdown) {
                return (LuaNil, message).into_lua_multi(lua);
            }
            let (config, resolve) = config_from(options)?;
            let mut failure: Option<LuaError> = None;
            let rendered = render(markdown, &config, &mut |href| match &resolve {
                None => Ok(href.to_string()),
                Some(f) => f.call::<String>(href).map_err(|e| {
                    failure = Some(e);
                    String::new()
                }),
            });
            match rendered {
                Ok(rendered) => rendered_to_lua(lua, rendered)?.into_lua_multi(lua),
                Err(message) => match failure {
                    Some(error) => Err(error),
                    // A refusal of the renderer itself (the output cap) is `nil, message` too.
                    None => (LuaNil, message).into_lua_multi(lua),
                },
            }
        })?,
    )?;
    #[cfg(feature = "spec-tests")]
    exports.set(
        "commonmark",
        lua.create_function(|_, (markdown, extension): (LuaString, Option<LuaString>)| {
            let extension = extension
                .map(|e| e.to_str().map(|e| e.to_string()))
                .transpose()?;
            let bytes = markdown.as_bytes();
            let text = check_input("markdown", &bytes).map_err(LuaError::runtime)?;
            Ok(commonmark(text, extension.as_deref()))
        })?,
    )?;
    exports.set(
        "highlight",
        lua.create_function(|_, (code, lang): (LuaString, LuaString)| {
            let (code, lang) = (code.as_bytes(), lang.as_bytes());
            let code = check_input("code", &code).map_err(LuaError::runtime)?;
            let lang = check_input("language", &lang).map_err(LuaError::runtime)?;
            Ok(highlight(code, lang))
        })?,
    )?;
    exports.set("MAX_INPUT_BYTES", MAX_INPUT_BYTES)?;
    exports.set("MAX_OUTPUT_BYTES", MAX_OUTPUT_BYTES)?;
    exports.set("MAX_OUTPUT_RATIO", MAX_OUTPUT_RATIO)?;
    exports.set("MAX_NESTING", MAX_NESTING)?;
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
    fn nesting_is_bounded_per_line() {
        assert!(check_nesting(&format!("{} x", "> ".repeat(MAX_NESTING))).is_ok());
        let err = check_nesting(&format!("a\n{} x", "- ".repeat(MAX_NESTING + 1))).unwrap_err();
        assert!(err.starts_with("line 2 "), "{err}");
        assert!(check_nesting(&format!("a {}", "> ".repeat(500))).is_ok());
        assert!(check_nesting(&format!("{}x", "1. ".repeat(MAX_NESTING + 1))).is_err());
        assert!(check_nesting(&format!("{}x", ">".repeat(200_000))).is_err());
    }

    #[test]
    fn plain_text_of_deep_documents_does_not_recurse() {
        let r = run(&format!("{}x *a _b_ c*\n", "> ".repeat(MAX_NESTING)));
        assert_eq!(r.sections[0].text, "x a b c");
    }

    fn ids(r: &Rendered) -> Vec<&str> {
        r.headings.iter().map(|h| h.id.as_str()).collect()
    }

    #[test]
    fn duplicate_headings_are_numbered_in_order() {
        let r = run("# h\n\n# h\n\n# h\n\n# h\n");
        assert_eq!(ids(&r), ["h", "h-1", "h-2", "h-3"]);
    }

    #[test]
    fn a_custom_identifier_that_collides_with_a_suffix_is_skipped() {
        let r = run("# h\n\n# x {#h-1}\n\n# h\n\n# h-1\n\n# h\n");
        assert_eq!(ids(&r), ["h", "h-1", "h-2", "h-1-1", "h-3"]);
        // The custom identifier comes first: the generated one must step over it.
        let r = run("# x {#h-1}\n\n# h\n\n# h\n\n# h\n");
        assert_eq!(ids(&r), ["h-1", "h", "h-2", "h-3"]);
        let unique: HashSet<_> = ids(&r).into_iter().collect();
        assert_eq!(unique.len(), 4);
    }

    #[test]
    fn identical_headings_cost_amortised_constant_time() {
        let count = 20_000;
        let source = "# h\n\n".repeat(count);
        let started = std::time::Instant::now();
        let r = run(&source);
        let elapsed = started.elapsed();
        assert_eq!(r.headings.len(), count);
        assert_eq!(r.headings[0].id, "h");
        assert_eq!(r.headings[1].id, "h-1");
        assert_eq!(r.headings[2].id, "h-2");
        assert_eq!(r.headings[count - 1].id, format!("h-{}", count - 1));
        // 40000 headings took 62 s when the search restarted at 1; generous bound for a slow CI host.
        assert!(
            elapsed < std::time::Duration::from_secs(20),
            "took {elapsed:?}"
        );
    }

    #[test]
    fn input_is_checked_for_size_then_utf8() {
        assert_eq!(check_input("markdown", b"fine"), Ok("fine"));
        let big = vec![b'a'; MAX_INPUT_BYTES + 1];
        let err = check_input("markdown", &big).unwrap_err();
        assert!(err.contains(&MAX_INPUT_BYTES.to_string()), "{err}");
        assert!(err.contains("8 MiB"), "{err}");
        assert!(check_input("markdown", &big[..MAX_INPUT_BYTES]).is_ok());
        let err = check_input("markdown", b"ab\xFFcd").unwrap_err();
        assert!(err.contains("not valid UTF-8"), "{err}");
        assert!(err.contains("position 3"), "{err}");
        assert!(check_input("code", b"\xC3")
            .unwrap_err()
            .starts_with("the code is not valid UTF-8"));
    }

    #[test]
    fn render_refuses_input_above_the_cap() {
        let big = "a".repeat(MAX_INPUT_BYTES + 1);
        let err = render(&big, &Config::default(), &mut |h| Ok(h.to_string())).unwrap_err();
        assert!(
            err.contains("more than the limit of 8388608 bytes"),
            "{err}"
        );
    }

    #[test]
    fn the_output_limit_has_a_floor_a_ratio_and_a_ceiling() {
        assert_eq!(output_limit(0), OUTPUT_FLOOR_BYTES);
        assert_eq!(output_limit(10), OUTPUT_FLOOR_BYTES);
        assert_eq!(
            output_limit(OUTPUT_FLOOR_BYTES),
            MAX_OUTPUT_RATIO * OUTPUT_FLOOR_BYTES
        );
        assert_eq!(
            output_limit(2 * OUTPUT_FLOOR_BYTES),
            2 * MAX_OUTPUT_RATIO * OUTPUT_FLOOR_BYTES
        );
        assert_eq!(output_limit(MAX_INPUT_BYTES), MAX_OUTPUT_BYTES);
        assert_eq!(output_limit(usize::MAX), MAX_OUTPUT_BYTES);
    }

    #[test]
    fn the_ratio_limit_stops_an_amplifying_document() {
        // Each reference writes a superscript link and a back-reference in the footnote: far more
        // than 32 bytes of HTML per 4 bytes of source, and the source is above the floor (1 MiB / 32).
        let source = format!("{}\n\n[^a]: note\n", "[^a]".repeat(100_000));
        let limit = MAX_OUTPUT_RATIO * source.len();
        assert!(limit > OUTPUT_FLOOR_BYTES && limit < MAX_OUTPUT_BYTES);
        let err = render(&source, &Config::default(), &mut |h| Ok(h.to_string())).unwrap_err();
        assert!(err.contains(&format!("larger than {limit} bytes")), "{err}");
        // The same document with a few references is well inside the limit.
        assert!(
            render("[^a]\n\n[^a]: note\n", &Config::default(), &mut |h| Ok(
                h.to_string()
            ))
            .is_ok()
        );
    }

    #[test]
    fn the_absolute_output_limit_stops_a_large_amplifying_document() {
        // About 7.5 MiB of source, so the ratio allows 240 MiB and the 64 MiB ceiling decides.
        let source = format!("{}\n\n[^a]: note\n", "[^a]".repeat(1_900_000));
        assert!(source.len() < MAX_INPUT_BYTES);
        assert!(output_limit(source.len()) == MAX_OUTPUT_BYTES);
        let err = render(&source, &Config::default(), &mut |h| Ok(h.to_string())).unwrap_err();
        assert!(err.contains(&MAX_OUTPUT_BYTES.to_string()), "{err}");
    }

    #[test]
    fn unknown_language_is_none() {
        assert!(highlight("x", "no-such-language").is_none());
    }
}
