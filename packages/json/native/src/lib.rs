//! JSON encoder for `hecate.json` (ADR 0020, ADR 0021: `serde_json` through `mlua`).
//!
//! `encode(value, options)` walks a Lua value and returns the JSON text, following the contract of
//! `hecate.json.internal.reference` (the value model, the number format, the escaping). It never
//! reports a failure itself: whenever the value cannot be encoded (ambiguous table, depth or size
//! limit, nesting beyond the native depth, non-finite number, invalid UTF-8, unsupported type) it returns `nil`, and the Lua side
//! asks the reference encoder, which produces the failure with its reason, message and path. So
//! the failure vocabulary exists once. `rfc8785` output is left to the reference encoder as well.
//!
//! What `serde_json` writes: string escapes, integers, punctuation and indentation (`CompactFormatter`,
//! `PrettyFormatter`). What stays ours, because it is the value model of the codec and not JSON syntax: the
//! walk of the Lua value (markers, array or object, holes, key order, limits), and the float text
//! (`Formatter::write_f64`: the fewest of 15 to 17 significant digits that read back, laid out as `%g`, with a
//! point or an exponent always present). The choice is recorded in OQ-52 and the spike report.
//!
//! Nothing here is `unsafe`; the Lua boundary is `mlua`.

use std::io::{self, Write};

use mlua::prelude::*;
use serde::ser::{Error as _, Serialize, SerializeMap, SerializeSeq, Serializer};
use serde_json::ser::{CompactFormatter, Formatter, PrettyFormatter};

const MARKERS_KEY: &str = "hecate.json.encoder_native.markers";
const HOLE_SLACK: i64 = 16;
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

/// `Write` that fails once more than `limit` bytes were written (the `max_size` option).
struct Limited {
    out: Vec<u8>,
    limit: usize,
}

impl Write for Limited {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        if self.out.len() + buf.len() > self.limit {
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
struct Floats<F: Formatter>(F);

macro_rules! delegate {
    ($($name:ident($($arg:ident: $ty:ty),*);)*) => {$(
        fn $name<W: ?Sized + Write>(&mut self, w: &mut W, $($arg: $ty),*) -> io::Result<()> {
            self.0.$name(w, $($arg),*)
        }
    )*};
}

impl<F: Formatter> Formatter for Floats<F> {
    fn write_f64<W: ?Sized + Write>(&mut self, w: &mut W, number: f64) -> io::Result<()> {
        write_float(w, number)
    }
    delegate! {
        begin_array(); end_array(); begin_object(); end_object();
        begin_array_value(first: bool); end_array_value();
        begin_object_key(first: bool); end_object_key();
        begin_object_value(); end_object_value();
    }
    fn write_i64<W: ?Sized + Write>(&mut self, w: &mut W, v: i64) -> io::Result<()> {
        self.0.write_i64(w, v)
    }
    fn write_string_fragment<W: ?Sized + Write>(&mut self, w: &mut W, f: &str) -> io::Result<()> {
        self.0.write_string_fragment(w, f)
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

/// A Lua value seen as a `Serialize`: the walk that carries the value model of the codec.
struct Node<'a> {
    value: &'a LuaValue,
    level: usize,
    markers: &'a Markers,
    options: &'a Options,
}

impl Serialize for Node<'_> {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        let unsupported = || S::Error::custom("unsupported");
        match self.value {
            LuaValue::String(s) => {
                let bytes = s.as_bytes();
                serializer.serialize_str(std::str::from_utf8(&bytes).map_err(|_| unsupported())?)
            }
            LuaValue::Integer(i) => serializer.serialize_i64(*i),
            LuaValue::Number(n) if n.is_finite() => serializer.serialize_f64(*n),
            LuaValue::Boolean(b) => serializer.serialize_bool(*b),
            LuaValue::Table(t) if *t == self.markers.null => serializer.serialize_unit(),
            LuaValue::Table(t) => self.table(t, serializer),
            _ => Err(unsupported()),
        }
    }
}

impl Node<'_> {
    fn table<S: Serializer>(&self, table: &LuaTable, serializer: S) -> Result<S::Ok, S::Error> {
        let unsupported = || S::Error::custom("unsupported");
        let level = self.level + 1;
        if level > self.options.max_depth || level > MAX_NATIVE_DEPTH {
            return Err(unsupported());
        }
        let mut entries: Vec<(LuaValue, LuaValue)> = Vec::new();
        for pair in table.pairs::<LuaValue, LuaValue>() {
            entries.push(pair.map_err(|_| unsupported())?);
        }
        let metatable = table.metatable();
        let marked_array = metatable.as_ref().is_some_and(|m| *m == self.markers.array);
        let marked_object = metatable
            .as_ref()
            .is_some_and(|m| *m == self.markers.object);
        let all_strings = entries
            .iter()
            .all(|(k, _)| matches!(k, LuaValue::String(_)));
        let inner = Node { level, ..*self };
        if marked_array || (!marked_object && !all_strings) {
            let mut highest: i64 = 0;
            for (key, _) in &entries {
                match key {
                    LuaValue::Integer(i) if *i >= 1 => highest = highest.max(*i),
                    _ => return Err(unsupported()),
                }
            }
            if highest > 2 * entries.len() as i64 + HOLE_SLACK {
                return Err(unsupported());
            }
            let mut slots: Vec<Option<&LuaValue>> = vec![None; highest as usize];
            for (key, value) in &entries {
                if let LuaValue::Integer(i) = key {
                    slots[*i as usize - 1] = Some(value);
                }
            }
            let mut seq = serializer.serialize_seq(Some(slots.len()))?;
            for slot in slots {
                match slot {
                    Some(value) => seq.serialize_element(&inner.child_of(value))?,
                    None => seq.serialize_element(&())?,
                }
            }
            seq.end()
        } else {
            let mut members: Vec<(String, &LuaValue)> = Vec::with_capacity(entries.len());
            for (key, value) in &entries {
                match key {
                    LuaValue::String(name) => {
                        let bytes = name.as_bytes();
                        let name = std::str::from_utf8(&bytes).map_err(|_| unsupported())?;
                        members.push((name.to_owned(), value));
                    }
                    _ => return Err(unsupported()),
                }
            }
            if self.options.canonical {
                members.sort_by(|a, b| a.0.encode_utf16().cmp(b.0.encode_utf16()));
            }
            let mut map = serializer.serialize_map(Some(members.len()))?;
            for (name, value) in members {
                map.serialize_entry(&name, &inner.child_of(value))?;
            }
            map.end()
        }
    }

    /// A node for a value one level below `self`'s container (`self.level` is already the container's).
    fn child_of<'b>(&'b self, value: &'b LuaValue) -> Node<'b> {
        Node {
            value,
            level: self.level,
            markers: self.markers,
            options: self.options,
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

fn run<F: Formatter>(formatter: F, node: &Node, limit: usize) -> Option<Vec<u8>> {
    let mut writer = Limited {
        out: Vec::new(),
        limit,
    };
    let mut serializer = serde_json::Serializer::with_formatter(&mut writer, Floats(formatter));
    node.serialize(&mut serializer).ok()?;
    Some(writer.out)
}

fn encode(lua: &Lua, (value, options): (LuaValue, LuaTable)) -> LuaResult<Option<LuaString>> {
    let markers = load_markers(lua)?;
    let options = read_options(&options)?;
    // The top-level value is at depth 0: its container is level 1.
    let node = Node {
        value: &value,
        level: 0,
        markers: &markers,
        options: &options,
    };
    let bytes = match &options.indent {
        Some(indent) => run(
            PrettyFormatter::with_indent(indent.as_bytes()),
            &node,
            options.max_size,
        ),
        None => run(CompactFormatter, &node, options.max_size),
    };
    match bytes {
        Some(bytes) => Ok(Some(lua.create_string(&bytes)?)),
        None => Ok(None),
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
