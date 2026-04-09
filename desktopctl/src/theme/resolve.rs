use crate::paths;
use crate::theme::schema::{ColorScheme, ThemeState};
use rusqlite::{Connection, params};
use serde_json::{Map, Value};
use std::{
    fs, io,
    path::{Path, PathBuf},
};

const HEX_COLOR_LEN: usize = 7;
const THEME_STATE_TABLE_SCHEMA: &str = "
    CREATE TABLE IF NOT EXISTS theme_state (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
    );
";

pub fn colors_dir() -> io::Result<PathBuf> {
    Ok(paths::repo_root()?.join("themes/colors"))
}

pub fn legacy_state_path() -> io::Result<PathBuf> {
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

pub fn load_state() -> crate::Result<ThemeState> {
    let db_path = paths::db_path()?;
    let legacy_path = legacy_state_path()?;
    load_state_from_paths(&db_path, &legacy_path)
}

pub fn save_state(state: &ThemeState) -> crate::Result<()> {
    let db_path = paths::db_path()?;
    save_state_to_db_path(state, &db_path)
}

pub fn serialize_state(state: &ThemeState) -> crate::Result<String> {
    Ok(format!(
        "{}\n",
        serde_json::to_string_pretty(&Value::Object(state.to_ordered_json_map()))?
    ))
}

fn load_state_from_paths(db_path: &Path, legacy_state_path: &Path) -> crate::Result<ThemeState> {
    let mut connection = open_state_db(db_path)?;
    initialize_state_storage(&mut connection, db_path, legacy_state_path)?;
    load_state_from_connection(&connection, db_path)
}

fn save_state_to_db_path(state: &ThemeState, db_path: &Path) -> crate::Result<()> {
    let mut connection = open_state_db(db_path)?;
    save_state_to_connection(state, &mut connection)
}

fn open_state_db(db_path: &Path) -> crate::Result<Connection> {
    if let Some(parent) = db_path.parent() {
        fs::create_dir_all(parent)?;
    }

    let connection = Connection::open(db_path)?;
    connection.execute_batch(THEME_STATE_TABLE_SCHEMA)?;
    Ok(connection)
}

fn initialize_state_storage(
    connection: &mut Connection,
    db_path: &Path,
    legacy_state_path: &Path,
) -> crate::Result<()> {
    if !theme_state_is_empty(connection)? {
        return Ok(());
    }

    if legacy_state_path.is_file() {
        let state = load_state_from_json_path(legacy_state_path)?;
        save_state_to_connection(&state, connection)?;
        eprintln!(
            "Imported theme state from {} into {}. You can delete {}.",
            legacy_state_path.display(),
            db_path.display(),
            legacy_state_path.display()
        );
        return Ok(());
    }

    save_state_to_connection(&ThemeState::default_state()?, connection)
}

fn theme_state_is_empty(connection: &Connection) -> crate::Result<bool> {
    let count = connection.query_row("SELECT COUNT(*) FROM theme_state", [], |row| {
        row.get::<_, i64>(0)
    })?;
    Ok(count == 0)
}

fn load_state_from_connection(
    connection: &Connection,
    db_path: &Path,
) -> crate::Result<ThemeState> {
    let mut statement = connection.prepare("SELECT key, value FROM theme_state ORDER BY key")?;
    let rows = statement.query_map([], |row| {
        Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
    })?;

    let mut map = Map::new();
    for row in rows {
        let (key, raw_value) = row?;
        let value = serde_json::from_str(&raw_value).map_err(|error| {
            invalid_data(format!(
                "{}: invalid JSON for key '{}': {error}",
                theme_state_label(db_path),
                key
            ))
        })?;
        map.insert(key, value);
    }

    let value = Value::Object(map);
    let label = theme_state_label(db_path);
    validate_theme_state(&value, &label)?;
    serde_json::from_value(value)
        .map_err(|error| invalid_data(format!("Invalid theme state in {label}: {error}")).into())
}

fn save_state_to_connection(state: &ThemeState, connection: &mut Connection) -> crate::Result<()> {
    let transaction = connection.transaction()?;
    transaction.execute("DELETE FROM theme_state", [])?;

    let mut insert = transaction.prepare("INSERT INTO theme_state (key, value) VALUES (?, ?)")?;
    for (key, value) in state.to_ordered_json_map() {
        insert.execute(params![key, serde_json::to_string(&value)?])?;
    }

    drop(insert);
    transaction.commit()?;
    Ok(())
}

fn load_state_from_json_path(state_path: &Path) -> crate::Result<ThemeState> {
    let value = parse_json_file(state_path)?;
    let label = state_path.display().to_string();
    validate_theme_state(&value, &label)?;
    serde_json::from_value(value).map_err(|error| {
        invalid_data(format!(
            "Invalid theme state in {}: {error}",
            state_path.display()
        ))
        .into()
    })
}

fn theme_state_label(db_path: &Path) -> String {
    format!("theme_state table in {}", db_path.display())
}

fn parse_json_file(path: &Path) -> crate::Result<Value> {
    let text = fs::read_to_string(path)?;
    serde_json::from_str(&text).map_err(|error| {
        invalid_data(format!("Invalid JSON in {}: {error}", path.display())).into()
    })
}

fn validate_color_scheme(value: &Value, path: &Path) -> crate::Result<()> {
    let object = expect_object(value, path.display().to_string())?;

    for key in ["family", "variant", "appearance", "colors", "palette"] {
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

fn validate_theme_state(value: &Value, label: &str) -> crate::Result<()> {
    let object = expect_object(value, label.to_owned())?;

    let mut missing = ThemeState::known_field_names()
        .iter()
        .copied()
        .filter(|name| !object.contains_key(*name))
        .collect::<Vec<_>>();
    missing.sort_unstable();
    if !missing.is_empty() {
        return Err(invalid_data(format!(
            "{label}: missing required keys: {}",
            missing.join(", ")
        ))
        .into());
    }

    let mut string_fields = ThemeState::string_field_names().to_vec();
    string_fields.sort_unstable();
    for name in string_fields {
        let value = object.get(name).expect("validated string field exists");
        if !matches!(value, Value::String(text) if !text.is_empty()) {
            return Err(
                invalid_data(format!("{label}: '{name}' must be a non-empty string")).into(),
            );
        }
    }

    let mut int_fields = ThemeState::int_field_names().to_vec();
    int_fields.sort_unstable();
    for name in int_fields {
        let value = object.get(name).expect("validated int field exists");
        if !matches!(value, Value::Number(number) if number.as_i64().is_some()) {
            return Err(invalid_data(format!("{label}: '{name}' must be an integer")).into());
        }
    }

    let mut bool_fields = ThemeState::bool_field_names().to_vec();
    bool_fields.sort_unstable();
    for name in bool_fields {
        let value = object.get(name).expect("validated bool field exists");
        if !matches!(value, Value::Bool(_)) {
            return Err(invalid_data(format!("{label}: '{name}' must be a boolean")).into());
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

    fn temp_path(name: &str, extension: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("time works")
            .as_nanos();
        std::env::temp_dir().join(format!("desktopctl-{name}-{nanos}.{extension}"))
    }

    fn expected_default_state_json() -> String {
        format!(
            concat!(
                "{{\n",
                "  \"color_scheme\": \"gruvbox-dark\",\n",
                "  \"wallpaper\": \"{}\",\n",
                "  \"filter_wallpaper\": false,\n",
                "  \"system_font\": \"Overpass\",\n",
                "  \"mono_font\": \"JetBrainsMono Nerd Font\",\n",
                "  \"icon_theme\": \"Neuwaita\",\n",
                "  \"cursor_theme\": \"BreezeX-RosePine-Linux\",\n",
                "  \"cursor_size\": 24,\n",
                "  \"font_size\": 11,\n",
                "  \"quickshell_font_size_offset\": 0,\n",
                "  \"mono_font_size\": 11,\n",
                "  \"alacritty_mono_font_size_offset\": 0,\n",
                "  \"ghostty_mono_font_size_offset\": 0,\n",
                "  \"gtk_mono_font_size_offset\": 0,\n",
                "  \"neovide_mono_font_size_offset\": 0,\n",
                "  \"qt_mono_font_size_offset\": 0,\n",
                "  \"vscode_mono_font_size_offset\": 3,\n",
                "  \"dark_hint\": true,\n",
                "  \"hypr_gaps_in\": 4,\n",
                "  \"hypr_gaps_out\": 6,\n",
                "  \"hypr_border_size\": 0,\n",
                "  \"hypr_rounding\": 8,\n",
                "  \"hypr_blur_enabled\": false,\n",
                "  \"hypr_blur_size\": 3,\n",
                "  \"hypr_blur_passes\": 4,\n",
                "  \"hypr_animations_enabled\": true\n",
                "}}\n"
            ),
            repo_root().join("wallpapers/lmao.png").display()
        )
    }

    #[test]
    fn empty_theme_state_db_initializes_defaults() -> TestResult {
        let db_path = temp_path("state-defaults", "db");
        let legacy_state_path = temp_path("missing-state", "json");

        let state = load_state_from_paths(&db_path, &legacy_state_path)?;
        assert_eq!(state, ThemeState::default_state()?);

        fs::remove_file(db_path)?;
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
    fn state_serialization_matches_legacy_output() -> TestResult {
        let state = ThemeState::default_state_for_repo_root(&repo_root());
        let rendered = serialize_state(&state)?;
        assert_eq!(rendered, expected_default_state_json());
        Ok(())
    }

    #[test]
    fn state_round_trip_preserves_unknown_fields() -> TestResult {
        let mut value: Value = serde_json::from_str(&expected_default_state_json())?;
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

        let legacy_path = temp_path("state-source", "json");
        let db_path = temp_path("state-saved", "db");
        fs::write(
            &legacy_path,
            format!("{}\n", serde_json::to_string_pretty(&value)?),
        )?;

        let state = load_state_from_paths(&db_path, &legacy_path)?;
        save_state_to_db_path(&state, &db_path)?;
        let saved: Value = serde_json::from_str(&serialize_state(&load_state_from_paths(
            &db_path,
            &temp_path("missing-state", "json"),
        )?)?)?;

        assert_eq!(saved["future_key"], Value::String("still here".to_owned()));
        assert_eq!(
            saved["future_nested"],
            serde_json::json!({ "alpha": 1, "beta": true })
        );

        fs::remove_file(legacy_path)?;
        fs::remove_file(db_path)?;
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
