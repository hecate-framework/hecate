//! JSON encoder for `hecate.json` (ADR 0020, ADR 0021: `serde_json` through `mlua`).
//!
//! `encode(value, options)` walks a Lua value and returns either the JSON text, or `nil` and a failure table
//! `{ reason, message, path }` (the reason, the message and the RFC 6901 JSON Pointer of the offending value). This
//! module is the only producer of the encoding failures of `hecate.json`: the vocabulary below (reasons and messages)
//! is the contract of `packages/json/tests/fixtures/encode_cases.lua`. Options arrive validated and complete:
//! `max_depth`, `max_size`, `indent` (a string or nil), `canonical` and `rfc8785` (booleans; `rfc8785` implies
//! `canonical`, is compact, writes every number as an IEEE double in the ECMAScript format of RFC 8785 section 3.2.2.3 and
//! rejects an integer beyond +-2^53).
//!
//! What `serde_json` writes: string escapes, integers, punctuation and indentation (`CompactFormatter`,
//! `PrettyFormatter`). What stays ours, because it is the value model of the codec and not JSON syntax: the
//! walk of the Lua value (markers, array or object, holes, key order, limits, failures), and the float text
//! (`Formatter::write_f64`: the fewest of 15 to 17 significant digits that read back, laid out as `%g`, with a
//! point or an exponent always present; or the RFC 8785 layout). The choice is recorded in OQ-52 and the spike report.
//!
//! A failure is found by the walk where it happens and carries its path on the way out: every container that the
//! error crosses adds its own step, so that a successful encoding records nothing.
//!
//! Nothing here is `unsafe`; the Lua boundary is `mlua`.

use std::cell::RefCell;
use std::io::{self, Write};

use mlua::prelude::*;
use serde::ser::{Error as _, Serialize, SerializeMap, SerializeSeq, Serializer};
use serde_json::ser::{CompactFormatter, Formatter, PrettyFormatter};

const MARKERS_KEY: &str = "hecate.json.encoder_native.markers";
const HOLE_SLACK: i64 = 16;
/// The deepest nesting walked, whatever `max_depth` says: the walk recurses on the native stack (1 MiB for the main
/// thread of a Windows process). It equals the highest `max_depth` that the public module accepts.
const DEPTH_CEILING: usize = 1000;
/// The largest integer that an IEEE double holds exactly (RFC 8785 section 3.2.2.3 via I-JSON, RFC 7493 section 2.2).
const MAX_SAFE_INTEGER: i64 = 1 << 53;

struct Markers {
    null: LuaTable,
    array: LuaTable,
    object: LuaTable,
}

struct Options {
    max_depth: usize,
    max_size: usize,
    indent: Option<String>,
    canonical: bool,
    rfc8785: bool,
}

/// One step of the path of a failure, from the offending value up to the top-level value.
enum Step {
    Index(usize),
    Key(Vec<u8>),
}

struct Failure {
    reason: &'static str,
    message: String,
    /// The steps in the order the error crossed them: innermost first.
    steps: Vec<Step>,
}

/// The failure of the encoding in progress, shared by the walk (a `Serialize` cannot return more than an error).
struct Outcome {
    failure: RefCell<Option<Failure>>,
}

impl Outcome {
    fn fail<E: serde::ser::Error>(&self, reason: &'static str, message: String) -> E {
        *self.failure.borrow_mut() = Some(Failure {
            reason,
            message,
            steps: Vec::new(),
        });
        E::custom(reason)
    }

    /// Adds the step of the container that an error crosses; nothing is recorded for an error that is not a failure of ours
    /// (the `max_size` limit, reported by the writer).
    fn through<T, E>(&self, result: Result<T, E>, step: impl FnOnce() -> Step) -> Result<T, E> {
        if result.is_err() {
            if let Some(failure) = self.failure.borrow_mut().as_mut() {
                failure.steps.push(step());
            }
        }
        result
    }
}

/// `Write` that fails once more than `limit` bytes were written (the `max_size` option).
struct Limited {
    out: Vec<u8>,
    limit: usize,
    overflowed: bool,
}

impl Write for Limited {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        if self.out.len() + buf.len() > self.limit {
            self.overflowed = true;
            return Err(io::Error::other("max_size"));
        }
        self.out.extend_from_slice(buf);
        Ok(buf.len())
    }
    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

/// Float layout of the codec on top of any serde_json formatter.
struct Floats<F: Formatter> {
    inner: F,
    rfc8785: bool,
}

macro_rules! delegate {
    ($($name:ident($($arg:ident: $ty:ty),*);)*) => {$(
        fn $name<W: ?Sized + Write>(&mut self, w: &mut W, $($arg: $ty),*) -> io::Result<()> {
            self.inner.$name(w, $($arg),*)
        }
    )*};
}

impl<F: Formatter> Formatter for Floats<F> {
    fn write_f64<W: ?Sized + Write>(&mut self, w: &mut W, number: f64) -> io::Result<()> {
        if self.rfc8785 {
            write_rfc8785_number(w, number)
        } else {
            write_float(w, number)
        }
    }
    delegate! {
        begin_array(); end_array(); begin_object(); end_object();
        begin_array_value(first: bool); end_array_value();
        begin_object_key(first: bool); end_object_key();
        begin_object_value(); end_object_value();
    }
    fn write_i64<W: ?Sized + Write>(&mut self, w: &mut W, v: i64) -> io::Result<()> {
        self.inner.write_i64(w, v)
    }
    fn write_string_fragment<W: ?Sized + Write>(&mut self, w: &mut W, f: &str) -> io::Result<()> {
        self.inner.write_string_fragment(w, f)
    }
}

fn write_float<W: ?Sized + Write>(w: &mut W, number: f64) -> io::Result<()> {
    let mut out = String::new();
    if number == 0.0 {
        out.push_str(if number.is_sign_negative() {
            "-0.0"
        } else {
            "0.0"
        });
        return w.write_all(out.as_bytes());
    }
    let mut scientific = String::new();
    for precision in 15..=17usize {
        scientific = format!("{:.*e}", precision - 1, number.abs());
        if scientific
            .parse::<f64>()
            .is_ok_and(|read| read == number.abs())
        {
            break;
        }
    }
    let (mantissa, exponent) = scientific.split_once('e').unwrap_or((&scientific, "0"));
    let exponent: i32 = exponent.parse().unwrap_or(0);
    let precision = mantissa.len() as i32 - 1;
    let mut digits: String = mantissa.chars().filter(|c| *c != '.').collect();
    digits.truncate(digits.trim_end_matches('0').len().max(1));
    if number < 0.0 {
        out.push('-');
    }
    if exponent < -4 || exponent >= precision {
        out.push_str(&digits[..1]);
        if digits.len() > 1 {
            out.push('.');
            out.push_str(&digits[1..]);
        }
        out.push_str(&format!(
            "e{}{:02}",
            if exponent < 0 { '-' } else { '+' },
            exponent.abs()
        ));
    } else if exponent >= 0 {
        let integral = exponent as usize + 1;
        if digits.len() <= integral {
            out.push_str(&digits);
            out.extend(std::iter::repeat_n('0', integral - digits.len()));
            out.push_str(".0");
        } else {
            out.push_str(&digits[..integral]);
            out.push('.');
            out.push_str(&digits[integral..]);
        }
    } else {
        out.push_str("0.");
        out.extend(std::iter::repeat_n('0', (-exponent - 1) as usize));
        out.push_str(&digits);
    }
    w.write_all(out.as_bytes())
}

/// RFC 8785 section 3.2.2.3 (via ECMAScript `Number::toString`): the shortest digits that read back as the same double,
/// laid out as digits, a decimal point or an exponent depending on the magnitude. Negative zero is `0`.
fn write_rfc8785_number<W: ?Sized + Write>(w: &mut W, number: f64) -> io::Result<()> {
    if number == 0.0 {
        return w.write_all(b"0");
    }
    let mut out = String::new();
    if number < 0.0 {
        out.push('-');
    }
    // `{:e}` writes the shortest digits that read back, as `d.ddde-7` or `de22`.
    let scientific = format!("{:e}", number.abs());
    let (mantissa, exponent) = scientific.split_once('e').unwrap_or((&scientific, "0"));
    let mut digits: String = mantissa.chars().filter(|c| *c != '.').collect();
    digits.truncate(digits.trim_end_matches('0').len().max(1));
    let k = digits.len() as i32;
    let n = exponent.parse::<i32>().unwrap_or(0) + 1; // value = 0.DIGITS * 10^n
    if k <= n && n <= 21 {
        out.push_str(&digits);
        out.extend(std::iter::repeat_n('0', (n - k) as usize));
    } else if 0 < n && n <= 21 {
        out.push_str(&digits[..n as usize]);
        out.push('.');
        out.push_str(&digits[n as usize..]);
    } else if -6 < n && n <= 0 {
        out.push_str("0.");
        out.extend(std::iter::repeat_n('0', (-n) as usize));
        out.push_str(&digits);
    } else {
        let e = n - 1;
        out.push_str(&digits[..1]);
        if k > 1 {
            out.push('.');
            out.push_str(&digits[1..]);
        }
        out.push('e');
        out.push(if e < 0 { '-' } else { '+' });
        out.push_str(&e.abs().to_string());
    }
    w.write_all(out.as_bytes())
}

/// RFC 8785 section 3.2.3: member names sort by their UTF-16 code units. The byte order of UTF-8 is the order of code
/// points, which differs only for a character beyond U+FFFF (a surrogate pair, D800-DFFF in UTF-16) against one in
/// U+E000-U+FFFF. Writing each beyond-BMP character as its two surrogates (CESU-8) makes the byte order equal the UTF-16
/// order. A byte sequence that is not UTF-8 is left as it is: the walk rejects the member name when it reaches it.
fn utf16_order_key(name: &[u8]) -> Vec<u8> {
    let mut key = Vec::with_capacity(name.len());
    let mut i = 0;
    while i < name.len() {
        let lead = name[i];
        if (0xF0..=0xF4).contains(&lead) && i + 3 < name.len() {
            if let Ok(text) = std::str::from_utf8(&name[i..i + 4]) {
                if let Some(c) = text.chars().next() {
                    let code = c as u32 - 0x10000;
                    for unit in [0xD800 + (code >> 10), 0xDC00 + (code & 0x3FF)] {
                        key.push(0xE0 | (unit >> 12) as u8);
                        key.push(0x80 | ((unit >> 6) & 0x3F) as u8);
                        key.push(0x80 | (unit & 0x3F) as u8);
                    }
                    i += 4;
                    continue;
                }
            }
        }
        key.push(lead);
        i += 1;
    }
    key
}

/// The Lua type name of a value, as `type` (or `math.type` for a number) says it.
fn type_name(value: &LuaValue) -> &'static str {
    match value {
        LuaValue::Nil => "nil",
        LuaValue::Boolean(_) => "boolean",
        LuaValue::Integer(_) => "integer",
        LuaValue::Number(_) => "float",
        LuaValue::String(_) => "string",
        LuaValue::Table(_) => "table",
        LuaValue::Function(_) => "function",
        LuaValue::Thread(_) => "thread",
        _ => "userdata",
    }
}

/// A member name as a `Serialize`: it fails, with the member as the offending value, when it is not UTF-8.
struct Name<'a> {
    bytes: &'a [u8],
    outcome: &'a Outcome,
}

impl Serialize for Name<'_> {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        match std::str::from_utf8(self.bytes) {
            Ok(text) => serializer.serialize_str(text),
            Err(_) => {
                let error: S::Error = self
                    .outcome
                    .fail("invalid_utf8", "string is not valid UTF-8".to_owned());
                if let Some(failure) = self.outcome.failure.borrow_mut().as_mut() {
                    failure.steps.push(Step::Key(self.bytes.to_vec()));
                }
                Err(error)
            }
        }
    }
}

/// A Lua value seen as a `Serialize`: the walk that carries the value model of the codec.
struct Node<'a> {
    value: &'a LuaValue,
    level: usize,
    markers: &'a Markers,
    options: &'a Options,
    outcome: &'a Outcome,
}

impl Serialize for Node<'_> {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        let outcome = self.outcome;
        match self.value {
            LuaValue::String(s) => {
                let bytes = s.as_bytes();
                match std::str::from_utf8(&bytes) {
                    Ok(text) => serializer.serialize_str(text),
                    Err(_) => {
                        Err(outcome.fail("invalid_utf8", "string is not valid UTF-8".to_owned()))
                    }
                }
            }
            LuaValue::Integer(i) if self.options.rfc8785 => {
                if !(-MAX_SAFE_INTEGER..=MAX_SAFE_INTEGER).contains(i) {
                    return Err(outcome.fail(
                        "integer_out_of_range",
                        format!(
                            "integer {i} is beyond +-2^53: RFC 8785 writes numbers as IEEE doubles, which would silently change it; write it as a string"
                        ),
                    ));
                }
                serializer.serialize_f64(*i as f64)
            }
            LuaValue::Integer(i) => serializer.serialize_i64(*i),
            LuaValue::Number(n) if n.is_finite() => serializer.serialize_f64(*n),
            LuaValue::Number(n) => {
                let shown = if n.is_nan() {
                    "nan"
                } else if *n > 0.0 {
                    "inf"
                } else {
                    "-inf"
                };
                Err(outcome.fail("non_finite_number", format!("{shown} is not a JSON number")))
            }
            LuaValue::Boolean(b) => serializer.serialize_bool(*b),
            LuaValue::Table(t) if *t == self.markers.null => serializer.serialize_unit(),
            LuaValue::Table(t) => self.table(t, serializer),
            other => Err(outcome.fail(
                "unsupported_type",
                format!(
                    "a value of type {} has no JSON representation",
                    type_name(other)
                ),
            )),
        }
    }
}

/// The entries of a table, read raw (no metamethod).
#[inline(never)]
fn raw_entries(table: &LuaTable) -> LuaResult<Vec<(LuaValue, LuaValue)>> {
    table.pairs::<LuaValue, LuaValue>().collect()
}

/// The length of a table written as an array: its highest index. A hole is written as `null`; holes are accepted while the
/// table stays dense enough (highest index at most twice the number of entries plus 16), so that a stray `t[1e9] = x`
/// cannot make the encoder write a billion nulls. `None` when a key is not a positive index or the table is too sparse.
fn array_length(entries: &[(LuaValue, LuaValue)]) -> Option<usize> {
    let mut highest: i64 = 0;
    for (key, _) in entries {
        match key {
            LuaValue::Integer(i) if *i >= 1 => highest = highest.max(*i),
            _ => return None,
        }
    }
    if highest > 2 * entries.len() as i64 + HOLE_SLACK {
        return None;
    }
    Some(highest as usize)
}

impl Node<'_> {
    #[inline(never)]
    fn table<S: Serializer>(&self, table: &LuaTable, serializer: S) -> Result<S::Ok, S::Error> {
        let outcome = self.outcome;
        let level = self.level + 1;
        let max_depth = self.options.max_depth.min(DEPTH_CEILING);
        if level > max_depth {
            return Err(outcome.fail(
                "depth_limit",
                format!("nesting deeper than max_depth ({max_depth})"),
            ));
        }
        let entries = raw_entries(table).map_err(S::Error::custom)?;
        let metatable = table.metatable();
        let marked_array = metatable.as_ref().is_some_and(|m| *m == self.markers.array);
        let marked_object = metatable
            .as_ref()
            .is_some_and(|m| *m == self.markers.object);
        let all_strings = entries
            .iter()
            .all(|(k, _)| matches!(k, LuaValue::String(_)));
        let inner = Node { level, ..*self };
        // An unmarked table is an array when all its keys are positive indices, an object when all its keys are strings
        // (an empty table is an object), and ambiguous otherwise. The two bodies are separate functions so that a
        // level of nesting costs the stack of one of them only (a value 1000 levels deep must fit in 1 MiB).
        if marked_array || (!marked_object && !all_strings) {
            inner.array_body(&entries, marked_array, serializer)
        } else {
            inner.object_body(entries, serializer)
        }
    }

    #[inline(never)]
    fn array_body<S: Serializer>(
        &self,
        entries: &[(LuaValue, LuaValue)],
        marked: bool,
        serializer: S,
    ) -> Result<S::Ok, S::Error> {
        let outcome = self.outcome;
        let Some(length) = array_length(entries) else {
            return Err(if marked {
                outcome.fail(
                    "sparse_array",
                    "array has a key that is not a positive index, or too many holes (a hole is written as null while the highest index is at most twice the number of entries plus 16)".to_owned(),
                )
            } else {
                outcome.fail(
                    "ambiguous_table",
                    "table is neither a sequence nor an object with string keys: mark it with json.array or json.object".to_owned(),
                )
            });
        };
        let mut slots: Vec<Option<&LuaValue>> = vec![None; length];
        for (key, value) in entries {
            if let LuaValue::Integer(i) = key {
                slots[*i as usize - 1] = Some(value);
            }
        }
        let mut seq = serializer.serialize_seq(Some(slots.len()))?;
        for (index, slot) in slots.into_iter().enumerate() {
            let written = match slot {
                Some(value) => seq.serialize_element(&self.child_of(value)),
                None => seq.serialize_element(&()),
            };
            outcome.through(written, || Step::Index(index))?;
        }
        seq.end()
    }

    #[inline(never)]
    fn object_body<S: Serializer>(
        &self,
        entries: Vec<(LuaValue, LuaValue)>,
        serializer: S,
    ) -> Result<S::Ok, S::Error> {
        let outcome = self.outcome;
        let mut members: Vec<(Vec<u8>, &LuaValue)> = Vec::with_capacity(entries.len());
        for (key, value) in &entries {
            match key {
                LuaValue::String(name) => members.push((name.as_bytes().to_vec(), value)),
                other => {
                    return Err(outcome.fail(
                        "ambiguous_table",
                        format!(
                            "object keys must be strings, got a key of type {}",
                            type_name(other)
                        ),
                    ))
                }
            }
        }
        if self.options.canonical {
            members.sort_by_cached_key(|member| utf16_order_key(&member.0));
        }
        let mut map = serializer.serialize_map(Some(members.len()))?;
        for (name, value) in members {
            let key = Name {
                bytes: &name,
                outcome,
            };
            map.serialize_key(&key)?;
            let written = map.serialize_value(&self.child_of(value));
            outcome.through(written, || Step::Key(name.clone()))?;
        }
        map.end()
    }

    /// A node for a value one level below `self`'s container (`self.level` is already the container's).
    fn child_of<'b>(&'b self, value: &'b LuaValue) -> Node<'b> {
        Node {
            value,
            level: self.level,
            markers: self.markers,
            options: self.options,
            outcome: self.outcome,
        }
    }
}

fn load_markers(lua: &Lua) -> LuaResult<Markers> {
    let table: LuaTable = lua.named_registry_value(MARKERS_KEY)?;
    Ok(Markers {
        null: table.get("null")?,
        array: table.get("array_metatable")?,
        object: table.get("object_metatable")?,
    })
}

fn flag(options: &LuaTable, name: &str) -> LuaResult<bool> {
    Ok(options.get::<LuaValue>(name)?.as_boolean().unwrap_or(false))
}

fn read_options(options: &LuaTable) -> LuaResult<Options> {
    let rfc8785 = flag(options, "rfc8785")?;
    Ok(Options {
        max_depth: options.get::<usize>("max_depth")?,
        max_size: options.get::<usize>("max_size")?,
        indent: options.get::<Option<String>>("indent")?,
        canonical: rfc8785 || flag(options, "canonical")?,
        rfc8785,
    })
}

fn run<F: Formatter>(
    formatter: F,
    node: &Node,
    options: &Options,
) -> Result<Vec<u8>, Option<&'static str>> {
    let mut writer = Limited {
        out: Vec::new(),
        limit: options.max_size,
        overflowed: false,
    };
    let floats = Floats {
        inner: formatter,
        rfc8785: options.rfc8785,
    };
    let mut serializer = serde_json::Serializer::with_formatter(&mut writer, floats);
    match node.serialize(&mut serializer) {
        Ok(()) => Ok(writer.out),
        Err(_) if node.outcome.failure.borrow().is_some() => Err(None),
        Err(_) if writer.overflowed => Err(Some("size_limit")),
        Err(_) => Err(Some("internal")),
    }
}

/// The JSON Pointer (RFC 6901 sections 3 and 5) of a failure: `~` is written `~0` and `/` is written `~1`.
fn pointer(steps: &[Step]) -> Vec<u8> {
    let mut path = Vec::new();
    for step in steps.iter().rev() {
        path.push(b'/');
        match step {
            Step::Index(index) => path.extend_from_slice(index.to_string().as_bytes()),
            Step::Key(name) => {
                for byte in name {
                    match byte {
                        b'~' => path.extend_from_slice(b"~0"),
                        b'/' => path.extend_from_slice(b"~1"),
                        other => path.push(*other),
                    }
                }
            }
        }
    }
    path
}

fn failure_table(lua: &Lua, reason: &str, message: &str, path: &[u8]) -> LuaResult<LuaTable> {
    let table = lua.create_table_with_capacity(0, 3)?;
    table.set("reason", reason)?;
    table.set("message", message)?;
    table.set("path", lua.create_string(path)?)?;
    Ok(table)
}

fn encode(
    lua: &Lua,
    (value, options): (LuaValue, LuaTable),
) -> LuaResult<(Option<LuaString>, Option<LuaTable>)> {
    let markers = load_markers(lua)?;
    let options = read_options(&options)?;
    let outcome = Outcome {
        failure: RefCell::new(None),
    };
    // The top-level value is at depth 0: its container is level 1.
    let node = Node {
        value: &value,
        level: 0,
        markers: &markers,
        options: &options,
        outcome: &outcome,
    };
    let result = match &options.indent {
        Some(indent) => run(
            PrettyFormatter::with_indent(indent.as_bytes()),
            &node,
            &options,
        ),
        None => run(CompactFormatter, &node, &options),
    };
    match result {
        Ok(bytes) => Ok((Some(lua.create_string(&bytes)?), None)),
        Err(None) => {
            let failure = outcome.failure.borrow_mut().take();
            let failure = failure.ok_or_else(|| LuaError::runtime("encoder lost its failure"))?;
            let path = pointer(&failure.steps);
            Ok((
                None,
                Some(failure_table(lua, failure.reason, &failure.message, &path)?),
            ))
        }
        Err(Some("size_limit")) => {
            let message = format!("output exceeds max_size ({} bytes)", options.max_size);
            Ok((None, Some(failure_table(lua, "size_limit", &message, b"")?)))
        }
        Err(Some(other)) => Err(LuaError::runtime(format!(
            "hecate.json.encoder_native: {other} error while encoding"
        ))),
    }
}

fn bind(lua: &Lua, markers: LuaTable) -> LuaResult<()> {
    for field in ["null", "array_metatable", "object_metatable"] {
        if !matches!(markers.get::<LuaValue>(field)?, LuaValue::Table(_)) {
            return Err(LuaError::runtime(format!(
                "markers.{field} must be a table"
            )));
        }
    }
    lua.set_named_registry_value(MARKERS_KEY, markers)
}

#[mlua::lua_module(name = "hecate_json_encoder_native")]
fn module(lua: &Lua) -> LuaResult<LuaTable> {
    let t = lua.create_table()?;
    t.set("bind", lua.create_function(bind)?)?;
    t.set("encode", lua.create_function(encode)?)?;
    Ok(t)
}
