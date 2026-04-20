use super::{Assembly, GeneratedContent, TargetMetadata};
use crate::theme::{
    atomic_write, expand_user_path, json,
    schema::{ColorScheme, ThemeState},
};
use serde_json::{Map, Value};
use std::{
    fs, io,
    path::{Component, Path},
};

pub const METADATA: TargetMetadata = TargetMetadata {
    name: "chromium",
    assembly: Assembly::Command,
    output_path: None,
    base_path: None,
    extra_outputs: &[],
    managed_paths: &["~/.config/chromium/<profile>/Preferences"],
    state_keys: &["system_font", "mono_font"],
    reload_cmd: None,
    comment: None,
    sync_safe: true,
};

const CHROMIUM_CONFIG_DIR: &str = "~/.config/chromium";
const DEFAULT_PROFILE_NAME: &str = "Default";
const LOCAL_STATE_FILE_NAME: &str = "Local State";
const PREFERENCES_FILE_NAME: &str = "Preferences";
const COMMON_SCRIPT: &str = "Zyyy";

pub fn generate(_colors: &ColorScheme, _state: &ThemeState) -> crate::Result<GeneratedContent> {
    Ok(GeneratedContent::commands(Vec::new()))
}

pub fn persist(_colors: &ColorScheme, state: &ThemeState) -> crate::Result<()> {
    write_active_preferences(&expand_user_path(CHROMIUM_CONFIG_DIR)?, state)
}

fn write_active_preferences(config_dir: &Path, state: &ThemeState) -> crate::Result<()> {
    for profile_name in active_profile_names(config_dir)? {
        write_preferences(
            &config_dir.join(profile_name).join(PREFERENCES_FILE_NAME),
            state,
        )?;
    }

    Ok(())
}

fn write_preferences(path: &Path, state: &ThemeState) -> crate::Result<()> {
    let mut root = load_preferences(path)?;
    merge_value(&mut root, font_preferences(state));
    clear_managed_font_sizes(&mut root);

    let Value::Object(_) = root else {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!("{}: expected top-level JSON object", path.display()),
        )
        .into());
    };

    let content = json::format_value(&root);
    atomic_write(path, content.as_bytes())
}

fn active_profile_names(config_dir: &Path) -> crate::Result<Vec<String>> {
    let local_state_path = config_dir.join(LOCAL_STATE_FILE_NAME);
    let Some(local_state) = load_optional_json_object(&local_state_path)? else {
        return Ok(vec![DEFAULT_PROFILE_NAME.to_owned()]);
    };

    let mut profile_names = Vec::new();
    if let Some(entries) = local_state
        .get("profile")
        .and_then(|profile| profile.get("last_active_profiles"))
        .and_then(Value::as_array)
    {
        for entry in entries {
            let Some(name) = entry.as_str() else {
                continue;
            };
            if !is_safe_profile_name(name) || profile_names.iter().any(|existing| existing == name)
            {
                continue;
            }
            profile_names.push(name.to_owned());
        }
    }

    if profile_names.is_empty() {
        profile_names.push(DEFAULT_PROFILE_NAME.to_owned());
    }

    Ok(profile_names)
}

fn load_preferences(path: &Path) -> crate::Result<Value> {
    if !path.exists() {
        return Ok(Value::Object(Map::new()));
    }

    let text = fs::read_to_string(path)?;
    if text.trim().is_empty() {
        return Ok(Value::Object(Map::new()));
    }

    let value: Value = serde_json::from_str(&text).map_err(|error| {
        io::Error::new(
            io::ErrorKind::InvalidData,
            format!("Invalid JSON in {}: {error}", path.display()),
        )
    })?;

    if !value.is_object() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!("{}: expected top-level JSON object", path.display()),
        )
        .into());
    }

    Ok(value)
}

fn load_optional_json_object(path: &Path) -> crate::Result<Option<Value>> {
    if !path.exists() {
        return Ok(None);
    }

    let text = fs::read_to_string(path)?;
    if text.trim().is_empty() {
        return Ok(None);
    }

    let Ok(value) = serde_json::from_str::<Value>(&text) else {
        return Ok(None);
    };

    if !value.is_object() {
        return Ok(None);
    }

    Ok(Some(value))
}

fn is_safe_profile_name(name: &str) -> bool {
    let mut components = Path::new(name).components();
    matches!(components.next(), Some(Component::Normal(_))) && components.next().is_none()
}

fn font_preferences(state: &ThemeState) -> Value {
    let mut standard = Map::new();
    standard.insert(
        COMMON_SCRIPT.to_owned(),
        Value::String(state.system_font.clone()),
    );

    let mut sans_serif = Map::new();
    sans_serif.insert(
        COMMON_SCRIPT.to_owned(),
        Value::String(state.system_font.clone()),
    );

    let mut serif = Map::new();
    serif.insert(
        COMMON_SCRIPT.to_owned(),
        Value::String(state.system_font.clone()),
    );

    let mut fixed = Map::new();
    fixed.insert(
        COMMON_SCRIPT.to_owned(),
        Value::String(state.mono_font.clone()),
    );

    let mut fonts = Map::new();
    fonts.insert("standard".to_owned(), Value::Object(standard));
    fonts.insert("sansserif".to_owned(), Value::Object(sans_serif));
    fonts.insert("serif".to_owned(), Value::Object(serif));
    fonts.insert("fixed".to_owned(), Value::Object(fixed));

    let mut webprefs = Map::new();
    webprefs.insert("fonts".to_owned(), Value::Object(fonts));

    let mut webkit = Map::new();
    webkit.insert("webprefs".to_owned(), Value::Object(webprefs));

    let mut root = Map::new();
    root.insert("webkit".to_owned(), Value::Object(webkit));
    Value::Object(root)
}

fn clear_managed_font_sizes(root: &mut Value) {
    let Some(webprefs) = root
        .get_mut("webkit")
        .and_then(Value::as_object_mut)
        .and_then(|webkit| webkit.get_mut("webprefs"))
        .and_then(Value::as_object_mut)
    else {
        return;
    };

    webprefs.remove("default_font_size");
    webprefs.remove("default_fixed_font_size");
}

fn merge_value(base: &mut Value, generated: Value) {
    match (base, generated) {
        (Value::Object(base_map), Value::Object(generated_map)) => {
            for (key, generated_value) in generated_map {
                match base_map.get_mut(&key) {
                    Some(base_value) => merge_value(base_value, generated_value),
                    None => {
                        base_map.insert(key, generated_value);
                    }
                }
            }
        }
        (base_value, generated_value) => {
            *base_value = generated_value;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::theme::targets::testsupport::dummy_state;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temp_path(name: &str) -> std::path::PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("time works")
            .as_nanos();
        std::env::temp_dir().join(format!("desktopctl-{name}-{nanos}.json"))
    }

    fn read_json(path: &Path) -> Value {
        serde_json::from_str(&fs::read_to_string(path).expect("preferences exist"))
            .expect("valid preferences json")
    }

    #[test]
    fn write_preferences_creates_webkit_font_settings() {
        let path = temp_path("chromium-fonts-create");
        write_preferences(&path, &dummy_state()).expect("write succeeds");
        let written = read_json(&path);

        assert_eq!(
            written["webkit"]["webprefs"]["fonts"]["standard"][COMMON_SCRIPT],
            Value::String("Overpass".to_owned())
        );
        assert_eq!(
            written["webkit"]["webprefs"]["fonts"]["fixed"][COMMON_SCRIPT],
            Value::String("JetBrains Mono Nerd Font".to_owned())
        );
        assert!(
            written["webkit"]["webprefs"]
                .get("default_font_size")
                .is_none()
        );
        assert!(
            written["webkit"]["webprefs"]
                .get("default_fixed_font_size")
                .is_none()
        );

        let _ = fs::remove_file(path);
    }

    #[test]
    fn write_active_preferences_uses_default_profile_when_local_state_is_missing() {
        let config_dir = temp_path("chromium-active-default");

        write_active_preferences(&config_dir, &dummy_state()).expect("write succeeds");
        let written = read_json(
            &config_dir
                .join(DEFAULT_PROFILE_NAME)
                .join(PREFERENCES_FILE_NAME),
        );

        assert_eq!(
            written["webkit"]["webprefs"]["fonts"]["standard"][COMMON_SCRIPT],
            Value::String("Overpass".to_owned())
        );

        let _ = fs::remove_dir_all(config_dir);
    }

    #[test]
    fn write_active_preferences_updates_all_safe_active_profiles() {
        let config_dir = temp_path("chromium-active-profiles");
        fs::create_dir_all(&config_dir).expect("config dir created");
        fs::write(
            config_dir.join(LOCAL_STATE_FILE_NAME),
            r#"{"profile":{"last_active_profiles":["Profile 1","../escape","Profile 1","Profile 2"]}}"#,
        )
        .expect("local state written");

        write_active_preferences(&config_dir, &dummy_state()).expect("write succeeds");

        assert!(
            config_dir
                .join("Profile 1")
                .join(PREFERENCES_FILE_NAME)
                .exists()
        );
        assert!(
            config_dir
                .join("Profile 2")
                .join(PREFERENCES_FILE_NAME)
                .exists()
        );
        assert!(
            !config_dir
                .join(DEFAULT_PROFILE_NAME)
                .join(PREFERENCES_FILE_NAME)
                .exists()
        );
        assert!(
            !config_dir
                .parent()
                .expect("has parent")
                .join("escape")
                .join(PREFERENCES_FILE_NAME)
                .exists()
        );

        let _ = fs::remove_dir_all(config_dir);
    }

    #[test]
    fn write_active_preferences_falls_back_to_default_when_local_state_is_invalid() {
        let config_dir = temp_path("chromium-active-invalid-local-state");
        fs::create_dir_all(&config_dir).expect("config dir created");
        fs::write(config_dir.join(LOCAL_STATE_FILE_NAME), "not json").expect("local state written");

        write_active_preferences(&config_dir, &dummy_state()).expect("write succeeds");

        assert!(
            config_dir
                .join(DEFAULT_PROFILE_NAME)
                .join(PREFERENCES_FILE_NAME)
                .exists()
        );

        let _ = fs::remove_dir_all(config_dir);
    }

    #[test]
    fn write_preferences_preserves_unmanaged_keys() {
        let path = temp_path("chromium-fonts-merge");
        fs::write(
            &path,
            r#"{"browser":{"show_home_button":true},"webkit":{"webprefs":{"javascript_enabled":true,"default_font_size":22,"default_fixed_font_size":18}}}"#,
        )
        .expect("fixture written");

        write_preferences(&path, &dummy_state()).expect("write succeeds");
        let written = read_json(&path);

        assert_eq!(written["browser"]["show_home_button"], Value::Bool(true));
        assert_eq!(
            written["webkit"]["webprefs"]["javascript_enabled"],
            Value::Bool(true)
        );
        assert_eq!(
            written["webkit"]["webprefs"]["fonts"]["sansserif"][COMMON_SCRIPT],
            Value::String("Overpass".to_owned())
        );
        assert!(
            written["webkit"]["webprefs"]
                .get("default_font_size")
                .is_none()
        );
        assert!(
            written["webkit"]["webprefs"]
                .get("default_fixed_font_size")
                .is_none()
        );

        let _ = fs::remove_file(path);
    }

    #[test]
    fn write_preferences_clears_managed_font_sizes() {
        let path = temp_path("chromium-clear-font-sizes");
        let mut state = dummy_state();
        state.font_size = 12;
        state.chromium_font_size_offset = 1;
        state.mono_font_size = 10;
        fs::write(
            &path,
            r#"{"webkit":{"webprefs":{"default_font_size":13,"default_fixed_font_size":10}}}"#,
        )
        .expect("fixture written");

        write_preferences(&path, &state).expect("write succeeds");
        let written = read_json(&path);

        assert!(
            written["webkit"]["webprefs"]
                .get("default_font_size")
                .is_none()
        );
        assert!(
            written["webkit"]["webprefs"]
                .get("default_fixed_font_size")
                .is_none()
        );

        let _ = fs::remove_file(path);
    }
}
