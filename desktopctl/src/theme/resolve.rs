use crate::paths;
use crate::theme::schema::{ColorScheme, FieldKind, THEME_FIELDS, ThemeState, field_names};
use rusqlite::{Connection, OptionalExtension, params};
use serde_json::{Map, Value};
use std::{
    fs, io,
    path::{Path, PathBuf},
};

const HEX_COLOR_LEN: usize = 7;
const THEME_TABLES_SCHEMA: &str = "
    CREATE TABLE IF NOT EXISTS theme_state (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS theme_presets (
        name  TEXT PRIMARY KEY,
        patch TEXT NOT NULL
    );
";

pub fn colors_dir() -> io::Result<PathBuf> {
    paths::data_path("colors")
}

pub fn load_colors(scheme_name: &str, colors_dir: &Path) -> crate::Result<ColorScheme> {
    let path = colors_dir.join(format!("{scheme_name}.json"));
    if !path.is_file() {
        let available = crate::theme::json_file_stems_by_filename(colors_dir)?;
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
        crate::invalid_data(format!(
            "Invalid color scheme in {}: {error}",
            path.display()
        ))
        .into()
    })
}

pub fn load_state() -> crate::Result<ThemeState> {
    load_state_from_db_path(&paths::db_path()?)
}

/// Upserts only the given keys so concurrent writers commute on disjoint keys.
pub fn save_state_keys(pairs: &[(&str, &Value)]) -> crate::Result<()> {
    let db_path = paths::db_path()?;
    save_state_keys_to_db_path(pairs, &db_path)
}

pub fn preset_names() -> crate::Result<Vec<String>> {
    let connection = open_state_db(&paths::db_path()?)?;
    let mut statement = connection.prepare("SELECT name FROM theme_presets ORDER BY name")?;
    let names = statement
        .query_map([], |row| row.get::<_, String>(0))?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(names)
}

pub fn load_preset(name: &str) -> crate::Result<Option<Value>> {
    let connection = open_state_db(&paths::db_path()?)?;
    let patch = connection
        .query_row(
            "SELECT patch FROM theme_presets WHERE name = ?",
            [name],
            |row| row.get::<_, String>(0),
        )
        .optional()?;
    patch
        .map(|text| {
            serde_json::from_str(&text).map_err(|error| {
                crate::invalid_data(format!("preset '{name}': invalid JSON: {error}")).into()
            })
        })
        .transpose()
}

pub fn save_preset(name: &str, patch: &Value) -> crate::Result<()> {
    let connection = open_state_db(&paths::db_path()?)?;
    connection.execute(
        "INSERT INTO theme_presets (name, patch) VALUES (?, ?) \
         ON CONFLICT(name) DO UPDATE SET patch = excluded.patch",
        params![name, serde_json::to_string(patch)?],
    )?;
    Ok(())
}

/// Returns whether a preset by that name existed.
pub fn delete_preset(name: &str) -> crate::Result<bool> {
    let connection = open_state_db(&paths::db_path()?)?;
    Ok(connection.execute("DELETE FROM theme_presets WHERE name = ?", [name])? > 0)
}

fn load_state_from_db_path(db_path: &Path) -> crate::Result<ThemeState> {
    let mut connection = open_state_db(db_path)?;
    initialize_state_storage(&mut connection)?;
    load_state_from_connection(&mut connection, db_path)
}

fn open_state_db(db_path: &Path) -> crate::Result<Connection> {
    let connection = crate::db::open_state_db_at(db_path)?;
    connection.execute_batch(THEME_TABLES_SCHEMA)?;
    Ok(connection)
}

fn initialize_state_storage(connection: &mut Connection) -> crate::Result<()> {
    if !theme_state_is_empty(connection)? {
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
                crate::invalid_data(format!(
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
        .map_err(|error| crate::invalid_data(format!("Invalid theme state in {label}: {error}")))?;

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

fn save_state_keys_to_db_path(pairs: &[(&str, &Value)], db_path: &Path) -> crate::Result<()> {
    let mut connection = open_state_db(db_path)?;
    let transaction = connection.transaction()?;

    let mut upsert = transaction.prepare(
        "INSERT INTO theme_state (key, value) VALUES (?, ?) \
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
    )?;
    for (key, value) in pairs {
        upsert.execute(params![key, serde_json::to_string(value)?])?;
    }

    drop(upsert);
    transaction.commit()?;
    Ok(())
}

fn normalize_theme_state_value(value: Value, label: &str) -> crate::Result<(Value, Vec<String>)> {
    let mut object = match value {
        Value::Object(object) => object,
        _ => {
            return Err(
                crate::invalid_data(format!("{label}: expected top-level JSON object")).into(),
            );
        }
    };

    let changed_keys = backfill_missing_theme_state_keys(&mut object)?;
    let normalized = Value::Object(object);
    validate_theme_state(&normalized, label)?;
    Ok((normalized, changed_keys))
}

fn backfill_missing_theme_state_keys(
    object: &mut Map<String, Value>,
) -> crate::Result<Vec<String>> {
    let missing = field_names()
        .filter(|name| !object.contains_key(*name))
        .collect::<Vec<_>>();

    if missing.is_empty() {
        return Ok(Vec::new());
    }

    let mut defaults = ThemeState::default_state()?.to_ordered_json_map();
    if missing.contains(&"dark_hint")
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
        crate::invalid_data(format!("Invalid JSON in {}: {error}", path.display())).into()
    })
}

fn validate_color_scheme(value: &Value, path: &Path) -> crate::Result<()> {
    let object = expect_object(value, path.display().to_string())?;

    for key in ["family", "variant", "appearance", "colors"] {
        if !object.contains_key(key) {
            return Err(crate::invalid_data(format!(
                "{}: missing required top-level key '{key}'",
                path.display()
            ))
            .into());
        }
    }

    let colors = object
        .get("colors")
        .and_then(Value::as_object)
        .ok_or_else(|| {
            crate::invalid_data(format!("{}: 'colors' must be an object", path.display()))
        })?;

    let mut missing = ColorScheme::known_color_fields()
        .iter()
        .copied()
        .filter(|name| !colors.contains_key(*name))
        .collect::<Vec<_>>();
    missing.sort_unstable();
    if !missing.is_empty() {
        return Err(crate::invalid_data(format!(
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

    Ok(())
}

fn validate_theme_state(value: &Value, label: &str) -> crate::Result<()> {
    let object = expect_object(value, label.to_owned())?;

    let mut missing = field_names()
        .filter(|name| !object.contains_key(*name))
        .collect::<Vec<_>>();
    missing.sort_unstable();
    if !missing.is_empty() {
        return Err(crate::invalid_data(format!(
            "{label}: missing required keys: {}",
            missing.join(", ")
        ))
        .into());
    }

    for spec in THEME_FIELDS {
        let value = object.get(spec.name).expect("validated field exists");
        match spec.kind {
            FieldKind::String => {
                if !matches!(value, Value::String(text) if !text.is_empty()) {
                    return Err(crate::invalid_data(format!(
                        "{label}: '{}' must be a non-empty string",
                        spec.name
                    ))
                    .into());
                }
            }
            FieldKind::Int => {
                let Some(number) = value.as_i64() else {
                    return Err(crate::invalid_data(format!(
                        "{label}: '{}' must be an integer",
                        spec.name
                    ))
                    .into());
                };
                if let Some(min) = spec.min
                    && number < min
                {
                    return Err(crate::invalid_data(format!(
                        "{label}: '{}' must be at least {min}",
                        spec.name
                    ))
                    .into());
                }
            }
            FieldKind::Bool => {
                if !value.is_boolean() {
                    return Err(crate::invalid_data(format!(
                        "{label}: '{}' must be a boolean",
                        spec.name
                    ))
                    .into());
                }
            }
        }
    }

    Ok(())
}

fn expect_object(value: &Value, label: String) -> crate::Result<&Map<String, Value>> {
    value.as_object().ok_or_else(|| {
        crate::invalid_data(format!("{label}: expected top-level JSON object")).into()
    })
}

fn check_hex(value: &Value, label: &str) -> crate::Result<()> {
    let Some(text) = value.as_str() else {
        return Err(crate::invalid_data(format!(
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
        Err(crate::invalid_data(format!(
            "{label}: expected '#rrggbb' hex color, got {}",
            json_repr(value)
        ))
        .into())
    }
}

fn json_repr(value: &Value) -> String {
    value.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::{ScopedEnvVar, TempDir, env_lock, repo_root, scoped_repo_paths};
    use std::error::Error;

    type TestResult = std::result::Result<(), Box<dyn Error + Send + Sync>>;

    fn seed_state() -> ThemeState {
        ThemeState::load_seed(&repo_root().join("styling"), &repo_root())
            .expect("committed state seed loads")
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

    #[test]
    fn empty_theme_state_db_initializes_defaults() -> TestResult {
        let _lock = env_lock();
        let _paths = scoped_repo_paths();
        let dir = TempDir::new("state-defaults")?;
        let db_path = dir.path().join("state.db");

        let state = load_state_from_db_path(&db_path)?;
        assert_eq!(state, ThemeState::default_state()?);
        Ok(())
    }

    #[test]
    fn state_round_trip_preserves_unknown_fields() -> TestResult {
        let _lock = env_lock();
        let _paths = scoped_repo_paths();
        let mut rows = seed_state().to_ordered_json_map();
        rows.insert(
            "future_key".to_owned(),
            Value::String("still here".to_owned()),
        );
        rows.insert(
            "future_nested".to_owned(),
            serde_json::json!({ "alpha": 1, "beta": true }),
        );

        let dir = TempDir::new("state-saved")?;
        let db_path = dir.path().join("state.db");
        write_state_rows_to_db(&db_path, &rows)?;

        let state = load_state_from_db_path(&db_path)?;
        let mut connection = open_state_db(&db_path)?;
        save_state_to_connection(&state, &mut connection)?;
        let reloaded = load_state_from_db_path(&db_path)?.to_ordered_json_map();

        assert_eq!(
            reloaded.get("future_key"),
            Some(&Value::String("still here".to_owned()))
        );
        assert_eq!(
            reloaded.get("future_nested"),
            Some(&serde_json::json!({ "alpha": 1, "beta": true }))
        );
        Ok(())
    }

    #[test]
    fn partial_theme_state_db_backfills_missing_keys_and_persists_upgrade() -> TestResult {
        let _lock = env_lock();
        let _paths = scoped_repo_paths();
        let dir = TempDir::new("state-partial-db")?;
        let db_path = dir.path().join("state.db");

        let mut partial = seed_state().to_ordered_json_map();
        partial.remove("quickshell_font_size_offset");
        partial.remove("gtk_font_size_offset");
        partial.remove("qt_font_size_offset");
        partial.insert(
            "future_key".to_owned(),
            Value::String("still here".to_owned()),
        );
        write_state_rows_to_db(&db_path, &partial)?;

        let state = load_state_from_db_path(&db_path)?;
        let seed = seed_state();
        assert_eq!(
            state.quickshell_font_size_offset,
            seed.quickshell_font_size_offset
        );
        assert_eq!(state.gtk_font_size_offset, seed.gtk_font_size_offset);
        assert_eq!(state.qt_font_size_offset, seed.qt_font_size_offset);
        assert_eq!(
            state.extra.get("future_key"),
            Some(&Value::String("still here".to_owned()))
        );

        let keys = state_db_keys(&db_path)?;
        for key in [
            "quickshell_font_size_offset",
            "gtk_font_size_offset",
            "qt_font_size_offset",
        ] {
            assert!(keys.contains(&key.to_owned()));
        }
        Ok(())
    }

    #[test]
    fn save_state_keys_upserts_only_the_given_keys() -> TestResult {
        let dir = TempDir::new("state-key-upsert")?;
        let db_path = dir.path().join("state.db");

        let mut rows = seed_state().to_ordered_json_map();
        rows.remove("font_size");
        let seeded_scheme = rows["color_scheme"].to_string();
        write_state_rows_to_db(&db_path, &rows)?;

        let mono_font = Value::String("CommitMono".to_owned());
        let font_size = Value::from(13);
        save_state_keys_to_db_path(
            &[("mono_font", &mono_font), ("font_size", &font_size)],
            &db_path,
        )?;

        let connection = open_state_db(&db_path)?;
        let stored = |key: &str| {
            connection.query_row(
                "SELECT value FROM theme_state WHERE key = ?",
                params![key],
                |row| row.get::<_, String>(0),
            )
        };
        assert_eq!(stored("mono_font")?, "\"CommitMono\"");
        assert_eq!(stored("font_size")?, "13");
        // Untouched keys keep their previous values.
        assert_eq!(stored("color_scheme")?, seeded_scheme);
        Ok(())
    }

    #[test]
    fn validate_theme_state_enforces_field_minimum_bounds() -> TestResult {
        let mut rows = seed_state().to_ordered_json_map();
        rows.insert("font_size".to_owned(), Value::from(0));
        assert!(validate_theme_state(&Value::Object(rows), "test state").is_err());

        let mut negative_offset = seed_state().to_ordered_json_map();
        negative_offset.insert("quickshell_font_size_offset".to_owned(), Value::from(-2));
        validate_theme_state(&Value::Object(negative_offset), "test state")?;
        Ok(())
    }

    #[test]
    fn presets_round_trip_through_the_database() -> TestResult {
        let _lock = env_lock();
        let data_home = TempDir::new("presets-db")?;
        let _data_home = ScopedEnvVar::set("XDG_DATA_HOME", data_home.path());
        let patch = serde_json::json!({ "color_scheme": "gruvbox-dark" });

        save_preset("gruvbox", &patch)?;
        assert_eq!(preset_names()?, vec!["gruvbox".to_owned()]);
        assert_eq!(load_preset("gruvbox")?, Some(patch));

        assert!(delete_preset("gruvbox")?);
        assert!(!delete_preset("gruvbox")?);
        assert_eq!(load_preset("gruvbox")?, None);
        assert!(preset_names()?.is_empty());
        Ok(())
    }
}
