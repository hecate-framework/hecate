//! JSON encoder for `hecate.json` (ADR 0021).
//!
//! `encode(value, options)` walks a Lua value and returns the JSON text, following the contract of
//! `hecate.json.internal.reference` (the value model, the number format, the escaping). It never
//! reports a failure itself: whenever the value cannot be encoded (ambiguous table, depth or size
//! limit, nesting beyond the native depth, non-finite number, invalid UTF-8, unsupported type) it returns `nil`, and the Lua side
//! asks the reference encoder, which produces the failure with its reason, message and path. So
//! the failure vocabulary exists once. `rfc8785` output is left to the reference encoder as well.
//!
//! Nothing here is `unsafe`; the Lua boundary is `mlua`.

use std::fmt::Write as _;

use mlua::prelude::*;

const MARKERS_KEY: &str = "hecate.json.encoder_native.markers";

/// A table with more entries than this ratio allows is not written as an array (the reference
/// rule: highest index at most twice the number of entries plus 16).
const HOLE_SLACK: i64 = 16;

/// Deeper values are left to the reference encoder: this encoder recurses on the native stack, which
/// is small on some platforms (1 MiB for the main thread of a Windows process), while `max_depth` may
/// be 10000.
const MAX_NATIVE_DEPTH: usize = 200;

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
}

/// The reason an encoder gives up; the reference encoder reports it.
struct Unsupported;

struct Encoder<'a> {
    out: String,
    markers: &'a Markers,
    options: &'a Options,
}

fn load_markers(lua: &Lua) -> LuaResult<Markers> {
    let table: LuaTable = lua.named_registry_value(MARKERS_KEY)?;
    Ok(Markers {
        null: table.get("null")?,
        array: table.get("array_metatable")?,
        object: table.get("object_metatable")?,
    })
}

/// The fewest of 15, 16 and 17 significant digits that read back as the same double (what
/// `%.15g`, `%.16g` and `%.17g` choose in the reference encoder), laid out as `%g` does, with a
/// decimal point or an exponent always present (a float must decode as a float again). Rust rounds
/// the exact binary value correctly, like the C library, so the digits agree.
fn write_float(out: &mut String, number: f64) -> Result<(), Unsupported> {
    if !number.is_finite() {
        return Err(Unsupported);
    }
    if number == 0.0 {
        out.push_str(if number.is_sign_negative() {
            "-0.0"
        } else {
            "0.0"
        });
        return Ok(());
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
    let (mantissa, exponent) = scientific.split_once('e').ok_or(Unsupported)?;
    let exponent: i32 = exponent.parse().map_err(|_| Unsupported)?;
    let precision = mantissa.len() as i32 - 1; // digits and the point: the precision of %g
    let mut digits: String = mantissa.chars().filter(|c| *c != '.').collect();
    digits.truncate(digits.trim_end_matches('0').len().max(1)); // %g drops trailing zeros
    if number < 0.0 {
        out.push('-');
    }
    if exponent < -4 || exponent >= precision {
        out.push_str(&digits[..1]);
        if digits.len() > 1 {
            out.push('.');
            out.push_str(&digits[1..]);
        }
        let _ = write!(
            out,
            "e{}{:02}",
            if exponent < 0 { '-' } else { '+' },
            exponent.abs()
        );
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
    Ok(())
}

/// RFC 8259 section 7: quotation mark, reverse solidus and the control characters are escaped.
fn write_string(out: &mut String, text: &str) {
    out.push('"');
    let mut start = 0;
    for (index, byte) in text.bytes().enumerate() {
        let escape = match byte {
            b'"' => "\\\"",
            b'\\' => "\\\\",
            0x08 => "\\b",
            0x0c => "\\f",
            b'\n' => "\\n",
            b'\r' => "\\r",
            b'\t' => "\\t",
            0..=0x1f => "",
            _ => continue,
        };
        out.push_str(&text[start..index]);
        if escape.is_empty() {
            let _ = write!(out, "\\u{byte:04x}");
        } else {
            out.push_str(escape);
        }
        start = index + 1;
    }
    out.push_str(&text[start..]);
    out.push('"');
}

impl Encoder<'_> {
    fn check_size(&self) -> Result<(), Unsupported> {
        if self.out.len() > self.options.max_size {
            Err(Unsupported)
        } else {
            Ok(())
        }
    }

    fn newline(&mut self, depth: usize) {
        if let Some(indent) = &self.options.indent {
            self.out.push('\n');
            for _ in 0..depth {
                self.out.push_str(indent);
            }
        }
    }

    fn string(&mut self, text: &LuaString) -> Result<(), Unsupported> {
        let bytes = text.as_bytes();
        let text = std::str::from_utf8(&bytes).map_err(|_| Unsupported)?;
        write_string(&mut self.out, text);
        self.check_size()
    }

    fn value(&mut self, value: &LuaValue, depth: usize) -> Result<(), Unsupported> {
        match value {
            LuaValue::String(s) => self.string(s)?,
            LuaValue::Integer(i) => {
                let _ = write!(self.out, "{i}");
            }
            LuaValue::Number(n) => write_float(&mut self.out, *n)?,
            LuaValue::Boolean(b) => self.out.push_str(if *b { "true" } else { "false" }),
            LuaValue::Table(t) => {
                if *t == self.markers.null {
                    self.out.push_str("null");
                } else {
                    self.table(t, depth + 1)?;
                }
            }
            _ => return Err(Unsupported),
        }
        self.check_size()
    }

    /// `level` is the nesting level of the container being written.
    fn table(&mut self, table: &LuaTable, level: usize) -> Result<(), Unsupported> {
        if level > self.options.max_depth || level > MAX_NATIVE_DEPTH {
            return Err(Unsupported);
        }
        let mut entries: Vec<(LuaValue, LuaValue)> = Vec::new();
        for pair in table.pairs::<LuaValue, LuaValue>() {
            entries.push(pair.map_err(|_| Unsupported)?);
        }
        let metatable = table.metatable();
        let marked_array = metatable.as_ref().is_some_and(|m| *m == self.markers.array);
        let marked_object = metatable
            .as_ref()
            .is_some_and(|m| *m == self.markers.object);
        let all_strings = entries
            .iter()
            .all(|(k, _)| matches!(k, LuaValue::String(_)));
        if marked_array || (!marked_object && !all_strings) {
            self.array(&entries, level)
        } else {
            self.object(entries, level)
        }
    }

    fn array(&mut self, entries: &[(LuaValue, LuaValue)], level: usize) -> Result<(), Unsupported> {
        let mut highest: i64 = 0;
        for (key, _) in entries {
            match key {
                LuaValue::Integer(i) if *i >= 1 => highest = highest.max(*i),
                _ => return Err(Unsupported),
            }
        }
        if highest > 2 * entries.len() as i64 + HOLE_SLACK {
            return Err(Unsupported);
        }
        if highest == 0 {
            self.out.push_str("[]");
            return Ok(());
        }
        let mut slots: Vec<Option<&LuaValue>> = vec![None; highest as usize];
        for (key, value) in entries {
            if let LuaValue::Integer(i) = key {
                slots[*i as usize - 1] = Some(value);
            }
        }
        self.out.push('[');
        for (index, slot) in slots.iter().enumerate() {
            if index > 0 {
                self.out.push(',');
            }
            self.newline(level);
            match slot {
                Some(value) => self.value(value, level)?,
                None => self.out.push_str("null"),
            }
        }
        self.newline(level - 1);
        self.out.push(']');
        Ok(())
    }

    fn object(
        &mut self,
        entries: Vec<(LuaValue, LuaValue)>,
        level: usize,
    ) -> Result<(), Unsupported> {
        if entries.is_empty() {
            self.out.push_str("{}");
            return Ok(());
        }
        let mut members: Vec<(LuaString, LuaValue)> = Vec::with_capacity(entries.len());
        for (key, value) in entries {
            match key {
                LuaValue::String(name) => members.push((name, value)),
                _ => return Err(Unsupported),
            }
        }
        if self.options.canonical {
            // RFC 8785 section 3.2.3: member names sort by their UTF-16 code units.
            let mut named: Vec<(String, LuaValue)> = Vec::with_capacity(members.len());
            for (name, value) in members {
                let bytes = name.as_bytes();
                let name = std::str::from_utf8(&bytes)
                    .map_err(|_| Unsupported)?
                    .to_owned();
                named.push((name, value));
            }
            named.sort_by(|a, b| a.0.encode_utf16().cmp(b.0.encode_utf16()));
            self.out.push('{');
            for (index, (name, value)) in named.iter().enumerate() {
                self.member(index, name, value, level)?;
            }
        } else {
            self.out.push('{');
            for (index, (name, value)) in members.iter().enumerate() {
                let bytes = name.as_bytes();
                let name = std::str::from_utf8(&bytes).map_err(|_| Unsupported)?;
                self.member(index, name, value, level)?;
            }
        }
        self.newline(level - 1);
        self.out.push('}');
        Ok(())
    }

    fn member(
        &mut self,
        index: usize,
        name: &str,
        value: &LuaValue,
        level: usize,
    ) -> Result<(), Unsupported> {
        if index > 0 {
            self.out.push(',');
        }
        self.newline(level);
        write_string(&mut self.out, name);
        self.out.push_str(if self.options.indent.is_some() {
            ": "
        } else {
            ":"
        });
        self.value(value, level)
    }
}

fn read_options(options: &LuaTable) -> LuaResult<Options> {
    Ok(Options {
        max_depth: options.get::<usize>("max_depth")?,
        max_size: options.get::<usize>("max_size")?,
        indent: options.get::<Option<String>>("indent")?,
        canonical: options
            .get::<LuaValue>("canonical")?
            .as_boolean()
            .unwrap_or(false),
    })
}

/// `encode(value, options) -> text | nil`: `nil` means "ask the reference encoder".
fn encode(lua: &Lua, (value, options): (LuaValue, LuaTable)) -> LuaResult<Option<LuaString>> {
    let markers = load_markers(lua)?;
    let options = read_options(&options)?;
    let mut encoder = Encoder {
        out: String::new(),
        markers: &markers,
        options: &options,
    };
    // `value` is the top-level value, at depth 0.
    match encoder.value(&value, 0) {
        Ok(()) => Ok(Some(lua.create_string(&encoder.out)?)),
        Err(Unsupported) => Ok(None),
    }
}

/// `bind(markers)`: the `null` sentinel and the two metatables of the Lua side, kept by identity.
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
