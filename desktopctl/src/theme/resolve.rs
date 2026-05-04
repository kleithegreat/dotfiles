use crate::paths;
use crate::theme::schema::{ColorScheme, ThemeState, canonicalize_theme_string_value};
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
    load_state_from_connection(&mut connection, db_path)
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
    connection: &mut Connection,
    db_path: &Path,
) -> crate::Result<ThemeState> {
    let mut map = Map::new();
    {
        let mut statement =
            connection.prepare("SELECT key, value FROM theme_state ORDER BY key")?;
        let rows = statement.query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })?;

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
    }

    let label = theme_state_label(db_path);
    let (value, backfilled_keys) = normalize_theme_state_value(Value::Object(map), &label)?;
    let state: ThemeState = serde_json::from_value(value)
        .map_err(|error| invalid_data(format!("Invalid theme state in {label}: {error}")))?;

    if !backfilled_keys.is_empty() {
        save_state_to_connection(&state, connection)?;
    }

    Ok(state)
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
    let (value, _) = normalize_theme_state_value(value, &label)?;
    let state = serde_json::from_value(value).map_err(|error| {
        invalid_data(format!(
            "Invalid theme state in {}: {error}",
            state_path.display()
        ))
    })?;
    Ok(state)
}

fn normalize_theme_state_value(value: Value, label: &str) -> crate::Result<(Value, Vec<String>)> {
    let mut object = match value {
        Value::Object(object) => object,
        _ => {
            return Err(invalid_data(format!("{label}: expected top-level JSON object")).into());
        }
    };

    let mut changed_keys = backfill_missing_theme_state_keys(&mut object)?;
    changed_keys.extend(canonicalize_theme_state_strings(&mut object));
    changed_keys.sort_unstable();
    changed_keys.dedup();
    let normalized = Value::Object(object);
    validate_theme_state(&normalized, label)?;
    Ok((normalized, changed_keys))
}

fn canonicalize_theme_state_strings(object: &mut Map<String, Value>) -> Vec<String> {
    let mut changed = Vec::new();

    for key in ThemeState::string_field_names() {
        let Some(Value::String(value)) = object.get_mut(*key) else {
            continue;
        };

        let canonical = canonicalize_theme_string_value(key, value);
        if canonical == value.as_str() {
            continue;
        }

        *value = canonical.into_owned();
        changed.push((*key).to_owned());
    }

    changed
}

fn backfill_missing_theme_state_keys(
    object: &mut Map<String, Value>,
) -> crate::Result<Vec<String>> {
    let missing = ThemeState::known_field_names()
        .iter()
        .copied()
        .filter(|name| !object.contains_key(*name))
        .collect::<Vec<_>>();

    if missing.is_empty() {
        return Ok(Vec::new());
    }

    let mut defaults = ThemeState::default_state()?.to_ordered_json_map();
    if missing.iter().any(|name| *name == "dark_hint")
        && let Some(Value::String(scheme_name)) = object.get("color_scheme")
        && let Ok(dir) = colors_dir()
        && let Ok(colors) = load_colors(scheme_name, &dir)
    {
        defaults.insert("dark_hint".to_owned(), Value::Bool(colors.is_dark()));
    }

    for key in &missing {
        let value = defaults
            .remove(*key)
            .expect("default theme state should include every known field");
        object.insert((*key).to_owned(), value);
    }

    Ok(missing.into_iter().map(str::to_owned).collect())
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
    use crate::test_support::{ScopedEnvVar, env_lock};
    use crate::theme::schema::{
        DEFAULT_CHROMIUM_FONT_SIZE_OFFSET, DEFAULT_GTK_FONT_SIZE_OFFSET,
        DEFAULT_QT_FONT_SIZE_OFFSET, DEFAULT_QUICKSHELL_FONT_SIZE_OFFSET,
    };
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

    fn remove_file_if_exists(path: &Path) -> std::io::Result<()> {
        match fs::remove_file(path) {
            Ok(()) => Ok(()),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(error),
        }
    }

    fn write_state_rows_to_db(db_path: &Path, rows: &Map<String, Value>) -> crate::Result<()> {
        let mut connection = open_state_db(db_path)?;
        let transaction = connection.transaction()?;
        transaction.execute("DELETE FROM theme_state", [])?;

        let mut insert =
            transaction.prepare("INSERT INTO theme_state (key, value) VALUES (?, ?)")?;
        for (key, value) in rows {
            insert.execute(params![key, serde_json::to_string(value)?])?;
        }

        drop(insert);
        transaction.commit()?;
        Ok(())
    }

    fn state_db_keys(db_path: &Path) -> crate::Result<Vec<String>> {
        let connection = open_state_db(db_path)?;
        let mut statement = connection.prepare("SELECT key FROM theme_state ORDER BY key")?;
        let rows = statement.query_map([], |row| row.get::<_, String>(0))?;

        let mut keys = Vec::new();
        for row in rows {
            keys.push(row?);
        }

        Ok(keys)
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
                "  \"gtk_font_size_offset\": 0,\n",
                "  \"qt_font_size_offset\": 0,\n",
                "  \"chromium_font_size_offset\": 0,\n",
                "  \"mono_font_size\": 11,\n",
                "  \"alacritty_mono_font_size_offset\": 0,\n",
                "  \"ghostty_mono_font_size_offset\": 0,\n",
                "  \"gtk_mono_font_size_offset\": 0,\n",
                "  \"neovide_mono_font_size_offset\": 0,\n",
                "  \"qt_mono_font_size_offset\": 0,\n",
                "  \"vscode_mono_font_size_offset\": 3,\n",
                "  \"zed_mono_font_size_offset\": 4,\n",
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
        let _lock = env_lock();
        let _repo = ScopedEnvVar::set("DESKTOPCTL_REPO", repo_root().as_os_str());
        let db_path = temp_path("state-defaults", "db");
        let legacy_state_path = temp_path("missing-state", "json");

        let state = load_state_from_paths(&db_path, &legacy_state_path)?;
        assert_eq!(state, ThemeState::default_state()?);

        remove_file_if_exists(&db_path)?;
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

        remove_file_if_exists(&legacy_path)?;
        remove_file_if_exists(&db_path)?;
        Ok(())
    }

    #[test]
    fn partial_theme_state_db_backfills_missing_keys_and_persists_upgrade() -> TestResult {
        let db_path = temp_path("state-partial-db", "db");
        let legacy_state_path = temp_path("missing-state", "json");

        let mut partial =
            ThemeState::default_state_for_repo_root(&repo_root()).to_ordered_json_map();
        partial.remove("quickshell_font_size_offset");
        partial.remove("gtk_font_size_offset");
        partial.remove("qt_font_size_offset");
        partial.remove("chromium_font_size_offset");
        partial.insert(
            "future_key".to_owned(),
            Value::String("still here".to_owned()),
        );
        write_state_rows_to_db(&db_path, &partial)?;

        let state = load_state_from_paths(&db_path, &legacy_state_path)?;
        assert_eq!(
            state.quickshell_font_size_offset,
            DEFAULT_QUICKSHELL_FONT_SIZE_OFFSET
        );
        assert_eq!(state.gtk_font_size_offset, DEFAULT_GTK_FONT_SIZE_OFFSET);
        assert_eq!(state.qt_font_size_offset, DEFAULT_QT_FONT_SIZE_OFFSET);
        assert_eq!(
            state.chromium_font_size_offset,
            DEFAULT_CHROMIUM_FONT_SIZE_OFFSET
        );
        assert_eq!(
            state.extra.get("future_key"),
            Some(&Value::String("still here".to_owned()))
        );

        let keys = state_db_keys(&db_path)?;
        for key in [
            "quickshell_font_size_offset",
            "gtk_font_size_offset",
            "qt_font_size_offset",
            "chromium_font_size_offset",
        ] {
            assert!(keys.contains(&key.to_owned()));
        }

        remove_file_if_exists(&db_path)?;
        remove_file_if_exists(&legacy_state_path)?;
        Ok(())
    }

    #[test]
    fn legacy_theme_state_import_backfills_missing_keys() -> TestResult {
        let db_path = temp_path("state-import-db", "db");
        let legacy_path = temp_path("state-import-legacy", "json");

        let mut legacy =
            ThemeState::default_state_for_repo_root(&repo_root()).to_ordered_json_map();
        legacy.insert(
            "color_scheme".to_owned(),
            Value::String("gruvbox-light".to_owned()),
        );
        legacy.remove("dark_hint");
        legacy.remove("quickshell_font_size_offset");
        legacy.insert(
            "future_key".to_owned(),
            Value::String("still here".to_owned()),
        );
        fs::write(
            &legacy_path,
            format!(
                "{}\n",
                serde_json::to_string_pretty(&Value::Object(legacy))?
            ),
        )?;

        let state = load_state_from_paths(&db_path, &legacy_path)?;
        assert_eq!(state.color_scheme, "gruvbox-light");
        assert!(!state.dark_hint);
        assert_eq!(
            state.quickshell_font_size_offset,
            DEFAULT_QUICKSHELL_FONT_SIZE_OFFSET
        );
        assert_eq!(
            state.extra.get("future_key"),
            Some(&Value::String("still here".to_owned()))
        );

        let keys = state_db_keys(&db_path)?;
        assert!(keys.contains(&"dark_hint".to_owned()));
        assert!(keys.contains(&"quickshell_font_size_offset".to_owned()));

        remove_file_if_exists(&legacy_path)?;
        remove_file_if_exists(&db_path)?;
        Ok(())
    }

    #[test]
    fn theme_state_load_canonicalizes_legacy_mono_font_aliases() -> TestResult {
        let db_path = temp_path("state-alias-db", "db");
        let legacy_state_path = temp_path("missing-state", "json");

        let mut rows = ThemeState::default_state_for_repo_root(&repo_root()).to_ordered_json_map();
        rows.insert(
            "mono_font".to_owned(),
            Value::String("JetBrains Mono Nerd Font".to_owned()),
        );
        write_state_rows_to_db(&db_path, &rows)?;

        let state = load_state_from_paths(&db_path, &legacy_state_path)?;
        assert_eq!(state.mono_font, "JetBrainsMono Nerd Font");

        let connection = open_state_db(&db_path)?;
        let stored = connection.query_row(
            "SELECT value FROM theme_state WHERE key = ?",
            params!["mono_font"],
            |row| row.get::<_, String>(0),
        )?;
        assert_eq!(stored, "\"JetBrainsMono Nerd Font\"");

        remove_file_if_exists(&db_path)?;
        remove_file_if_exists(&legacy_state_path)?;
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
