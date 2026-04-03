use crate::paths;
use crate::theme::schema::{ColorScheme, ThemeState};
use serde_json::{Map, Value};
use std::{
    fs, io,
    path::{Path, PathBuf},
};

const HEX_COLOR_LEN: usize = 7;

pub fn colors_dir() -> io::Result<PathBuf> {
    Ok(paths::repo_root()?.join("themes/colors"))
}

pub fn state_path() -> io::Result<PathBuf> {
    Ok(paths::repo_root()?.join("themes/state.json"))
}

pub fn load_colors(scheme_name: &str, colors_dir: &Path) -> crate::Result<ColorScheme> {
    let path = colors_dir.join(format!("{scheme_name}.json"));
    if !path.is_file() {
        let mut available = Vec::new();
        for entry in fs::read_dir(colors_dir)? {
            let entry = entry?;
            let entry_path = entry.path();
            if entry_path
                .extension()
                .is_some_and(|extension| extension == "json")
                && let Some(stem) = entry_path.file_stem().and_then(|stem| stem.to_str())
            {
                available.push(stem.to_owned());
            }
        }
        available.sort();

        let available = if available.is_empty() {
            "(none)".to_owned()
        } else {
            available.join(", ")
        };

        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            format!(
                "Color scheme '{scheme_name}' not found at {}. Available: {available}",
                path.display()
            ),
        )
        .into());
    }

    let value = parse_json_file(&path)?;
    validate_color_scheme(&value, &path)?;
    serde_json::from_value(value).map_err(|error| {
        invalid_data(format!(
            "Invalid color scheme in {}: {error}",
            path.display()
        ))
        .into()
    })
}

pub fn load_state(state_path: &Path) -> crate::Result<ThemeState> {
    if !state_path.is_file() {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            format!("Theme state file not found: {}", state_path.display()),
        )
        .into());
    }

    let value = parse_json_file(state_path)?;
    validate_theme_state(&value, state_path)?;
    serde_json::from_value(value).map_err(|error| {
        invalid_data(format!(
            "Invalid theme state in {}: {error}",
            state_path.display()
        ))
        .into()
    })
}

pub fn save_state(state: &ThemeState, state_path: &Path) -> crate::Result<()> {
    fs::write(state_path, serialize_state(state)?)?;
    Ok(())
}

pub fn serialize_state(state: &ThemeState) -> crate::Result<String> {
    Ok(format!(
        "{}\n",
        serde_json::to_string_pretty(&Value::Object(state.to_ordered_json_map()))?
    ))
}

fn parse_json_file(path: &Path) -> crate::Result<Value> {
    let text = fs::read_to_string(path)?;
    serde_json::from_str(&text).map_err(|error| {
        invalid_data(format!("Invalid JSON in {}: {error}", path.display())).into()
    })
}

fn validate_color_scheme(value: &Value, path: &Path) -> crate::Result<()> {
    let object = expect_object(value, path.display().to_string())?;

    for key in ["family", "variant", "colors", "palette"] {
        if !object.contains_key(key) {
            return Err(invalid_data(format!(
                "{}: missing required top-level key '{key}'",
                path.display()
            ))
            .into());
        }
    }

    let colors = object
        .get("colors")
        .and_then(Value::as_object)
        .ok_or_else(|| invalid_data(format!("{}: 'colors' must be an object", path.display())))?;

    let mut missing = ColorScheme::known_color_fields()
        .iter()
        .copied()
        .filter(|name| !colors.contains_key(*name))
        .collect::<Vec<_>>();
    missing.sort_unstable();
    if !missing.is_empty() {
        return Err(invalid_data(format!(
            "{}: missing color keys: {}",
            path.display(),
            missing.join(", ")
        ))
        .into());
    }

    let mut color_names = ColorScheme::known_color_fields().to_vec();
    color_names.sort_unstable();
    for name in color_names {
        let value = colors.get(name).expect("validated color key exists");
        check_hex(value, &format!("{} colors.{name}", path.display()))?;
    }

    let palette = object.get("palette").ok_or_else(|| {
        invalid_data(format!(
            "{}: missing required top-level key 'palette'",
            path.display()
        ))
    })?;
    let Some(entries) = palette.as_array() else {
        return Err(invalid_data(format!(
            "{}: 'palette' must be a list of exactly 16 hex colors",
            path.display()
        ))
        .into());
    };
    if entries.len() != 16 {
        return Err(invalid_data(format!(
            "{}: 'palette' must be a list of exactly 16 hex colors",
            path.display()
        ))
        .into());
    }

    for (index, entry) in entries.iter().enumerate() {
        check_hex(entry, &format!("{} palette[{index}]", path.display()))?;
    }

    Ok(())
}

fn validate_theme_state(value: &Value, path: &Path) -> crate::Result<()> {
    let object = expect_object(value, path.display().to_string())?;

    let mut missing = ThemeState::known_field_names()
        .iter()
        .copied()
        .filter(|name| !object.contains_key(*name))
        .collect::<Vec<_>>();
    missing.sort_unstable();
    if !missing.is_empty() {
        return Err(invalid_data(format!(
            "{}: missing required keys: {}",
            path.display(),
            missing.join(", ")
        ))
        .into());
    }

    let mut string_fields = ThemeState::string_field_names().to_vec();
    string_fields.sort_unstable();
    for name in string_fields {
        let value = object.get(name).expect("validated string field exists");
        if !matches!(value, Value::String(text) if !text.is_empty()) {
            return Err(invalid_data(format!(
                "{}: '{name}' must be a non-empty string",
                path.display()
            ))
            .into());
        }
    }

    let mut int_fields = ThemeState::int_field_names().to_vec();
    int_fields.sort_unstable();
    for name in int_fields {
        let value = object.get(name).expect("validated int field exists");
        if !matches!(value, Value::Number(number) if number.as_i64().is_some()) {
            return Err(
                invalid_data(format!("{}: '{name}' must be an integer", path.display())).into(),
            );
        }
    }

    let mut bool_fields = ThemeState::bool_field_names().to_vec();
    bool_fields.sort_unstable();
    for name in bool_fields {
        let value = object.get(name).expect("validated bool field exists");
        if !matches!(value, Value::Bool(_)) {
            return Err(
                invalid_data(format!("{}: '{name}' must be a boolean", path.display())).into(),
            );
        }
    }

    Ok(())
}

fn expect_object(value: &Value, label: String) -> crate::Result<&Map<String, Value>> {
    value
        .as_object()
        .ok_or_else(|| invalid_data(format!("{label}: expected top-level JSON object")).into())
}

fn check_hex(value: &Value, label: &str) -> crate::Result<()> {
    let Some(text) = value.as_str() else {
        return Err(invalid_data(format!(
            "{label}: expected '#rrggbb' hex color, got {}",
            json_repr(value)
        ))
        .into());
    };

    let is_hex = text.len() == HEX_COLOR_LEN
        && text.starts_with('#')
        && text.as_bytes()[1..]
            .iter()
            .all(|byte| byte.is_ascii_hexdigit());

    if is_hex {
        Ok(())
    } else {
        Err(invalid_data(format!(
            "{label}: expected '#rrggbb' hex color, got {}",
            json_repr(value)
        ))
        .into())
    }
}

fn json_repr(value: &Value) -> String {
    value.to_string()
}

fn invalid_data(message: String) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, message)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::error::Error;
    use std::time::{SystemTime, UNIX_EPOCH};

    type TestResult = std::result::Result<(), Box<dyn Error + Send + Sync>>;

    fn repo_root() -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .expect("desktopctl lives under the repo root")
            .to_path_buf()
    }

    fn temp_path(name: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("time works")
            .as_nanos();
        std::env::temp_dir().join(format!("desktopctl-{name}-{nanos}.json"))
    }

    #[test]
    fn current_state_json_deserializes() -> TestResult {
        let path = repo_root().join("themes/state.json");
        let state = load_state(&path)?;
        assert_eq!(state.color_scheme, "gruvbox-dark");
        assert!(state.extra.is_empty());
        Ok(())
    }

    #[test]
    fn current_color_scheme_json_deserializes() -> TestResult {
        let scheme = load_colors("gruvbox-dark", &repo_root().join("themes/colors"))?;
        assert_eq!(scheme.family, "gruvbox");
        assert_eq!(scheme.variant, "dark");
        assert_eq!(scheme.palette.len(), 16);
        Ok(())
    }

    #[test]
    fn state_serialization_matches_python_output() -> TestResult {
        let path = repo_root().join("themes/state.json");
        let state = load_state(&path)?;
        let rendered = serialize_state(&state)?;
        let existing = fs::read_to_string(path)?;
        assert_eq!(rendered, existing);
        Ok(())
    }

    #[test]
    fn state_round_trip_preserves_unknown_fields() -> TestResult {
        let original = fs::read_to_string(repo_root().join("themes/state.json"))?;
        let mut value: Value = serde_json::from_str(&original)?;
        let object = value
            .as_object_mut()
            .expect("state fixture should remain a JSON object");
        object.insert(
            "future_key".to_owned(),
            Value::String("still here".to_owned()),
        );
        object.insert(
            "future_nested".to_owned(),
            serde_json::json!({ "alpha": 1, "beta": true }),
        );

        let source_path = temp_path("state-source");
        let saved_path = temp_path("state-saved");
        fs::write(
            &source_path,
            format!("{}\n", serde_json::to_string_pretty(&value)?),
        )?;

        let state = load_state(&source_path)?;
        save_state(&state, &saved_path)?;
        let saved: Value = serde_json::from_str(&fs::read_to_string(&saved_path)?)?;

        assert_eq!(saved["future_key"], Value::String("still here".to_owned()));
        assert_eq!(
            saved["future_nested"],
            serde_json::json!({ "alpha": 1, "beta": true })
        );

        fs::remove_file(source_path)?;
        fs::remove_file(saved_path)?;
        Ok(())
    }

    #[test]
    fn color_scheme_struct_uses_nested_wire_format() -> TestResult {
        let text = fs::read_to_string(repo_root().join("themes/colors/gruvbox-dark.json"))?;
        let scheme: ColorScheme = serde_json::from_str(&text)?;
        let value = serde_json::to_value(&scheme)?;
        assert!(value.get("colors").is_some());
        assert_eq!(value["colors"]["bg"], "#282828");
        Ok(())
    }
}
