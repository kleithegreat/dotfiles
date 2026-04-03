use serde::Serialize;
use serde_json::Value;

pub fn to_python_string<T>(value: &T) -> crate::Result<String>
where
    T: Serialize,
{
    let value = serde_json::to_value(value)?;
    Ok(format_value(&value))
}

pub fn format_pretty_value(value: &Value) -> String {
    let mut output = String::new();
    write_value(value, 0, true, &mut output);
    output
}

pub fn format_value(value: &Value) -> String {
    let mut output = String::new();
    write_value(value, 0, false, &mut output);
    output
}

fn write_value(value: &Value, indent: usize, pretty: bool, output: &mut String) {
    match value {
        Value::Null => output.push_str("null"),
        Value::Bool(value) => output.push_str(if *value { "true" } else { "false" }),
        Value::Number(value) => output.push_str(&value.to_string()),
        Value::String(value) => write_json_string(value, output),
        Value::Array(items) => write_array(items, indent, pretty, output),
        Value::Object(map) => write_object(map, indent, pretty, output),
    }
}

fn write_array(items: &[Value], indent: usize, pretty: bool, output: &mut String) {
    if items.is_empty() {
        output.push_str("[]");
        return;
    }

    if !pretty {
        output.push('[');
        for (index, item) in items.iter().enumerate() {
            write_value(item, indent + 1, false, output);
            if index + 1 != items.len() {
                output.push_str(", ");
            }
        }
        output.push(']');
        return;
    }

    output.push('[');
    output.push('\n');
    for (index, item) in items.iter().enumerate() {
        push_indent(indent + 1, output);
        write_value(item, indent + 1, true, output);
        if index + 1 != items.len() {
            output.push(',');
        }
        output.push('\n');
    }
    push_indent(indent, output);
    output.push(']');
}

fn write_object(
    map: &serde_json::Map<String, Value>,
    indent: usize,
    pretty: bool,
    output: &mut String,
) {
    if map.is_empty() {
        output.push_str("{}");
        return;
    }

    if !pretty {
        output.push('{');
        let len = map.len();
        for (index, (key, value)) in map.iter().enumerate() {
            write_json_string(key, output);
            output.push_str(": ");
            write_value(value, indent + 1, false, output);
            if index + 1 != len {
                output.push_str(", ");
            }
        }
        output.push('}');
        return;
    }

    output.push('{');
    output.push('\n');
    let len = map.len();
    for (index, (key, value)) in map.iter().enumerate() {
        push_indent(indent + 1, output);
        write_json_string(key, output);
        output.push_str(": ");
        write_value(value, indent + 1, true, output);
        if index + 1 != len {
            output.push(',');
        }
        output.push('\n');
    }
    push_indent(indent, output);
    output.push('}');
}

fn write_json_string(value: &str, output: &mut String) {
    output.push('"');

    for character in value.chars() {
        match character {
            '"' => output.push_str("\\\""),
            '\\' => output.push_str("\\\\"),
            '\u{08}' => output.push_str("\\b"),
            '\u{0c}' => output.push_str("\\f"),
            '\n' => output.push_str("\\n"),
            '\r' => output.push_str("\\r"),
            '\t' => output.push_str("\\t"),
            character if character <= '\u{1f}' => {
                output.push_str(&format!("\\u{:04x}", character as u32));
            }
            character if character.is_ascii() => output.push(character),
            character => {
                let mut buffer = [0u16; 2];
                for unit in character.encode_utf16(&mut buffer).iter() {
                    output.push_str(&format!("\\u{:04x}", unit));
                }
            }
        }
    }

    output.push('"');
}

fn push_indent(indent: usize, output: &mut String) {
    for _ in 0..indent {
        output.push_str("  ");
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn pretty_json_matches_python_ascii_behavior() {
        let value = json!({
            "theme": "Rosé Pine Dawn",
            "fonts": ["JetBrains Mono", "Frappe"],
        });

        assert_eq!(
            format_pretty_value(&value),
            "{\n  \"theme\": \"Ros\\u00e9 Pine Dawn\",\n  \"fonts\": [\n    \"JetBrains Mono\",\n    \"Frappe\"\n  ]\n}"
        );
    }

    #[test]
    fn compact_json_matches_python_ascii_behavior() {
        let value = json!({
            "theme": "Catppuccin Frappé",
            "enabled": true,
        });

        assert_eq!(
            format_value(&value),
            "{\"theme\": \"Catppuccin Frapp\\u00e9\", \"enabled\": true}"
        );
    }
}
