use super::Target;
use crate::{
    fs_util::{atomic_write, expand_user_path},
    theme::{
        orchestrator::merge_json_values,
        schema::{ColorScheme, ThemeState},
    },
};
use serde_json::{Map, Value};
use std::{
    fs,
    path::{Component, Path},
};

pub const TARGET: Target = Target::hooks("helium", &["system_font", "mono_font"]).persist(persist);

const HELIUM_CONFIG_DIR: &str = "~/.config/net.imput.helium";
const DEFAULT_PROFILE_NAME: &str = "Default";
const LOCAL_STATE_FILE_NAME: &str = "Local State";
const PREFERENCES_FILE_NAME: &str = "Preferences";
const COMMON_SCRIPT: &str = "Zyyy";
/// "Device": follow the portal's live `color-scheme`, which the gtk target sets.
const COLOR_SCHEME_DEVICE: i64 = 0;

pub(crate) fn mark_clean_exit() -> crate::Result<()> {
    mark_clean_exit_in(&expand_user_path(HELIUM_CONFIG_DIR)?)
}

pub fn persist(_colors: &ColorScheme, state: &ThemeState) -> crate::Result<()> {
    write_active_preferences(&expand_user_path(HELIUM_CONFIG_DIR)?, state)
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

/// Record a clean exit in every active profile. A browser that was killed
/// with the session opens a blank window offering to restore; one that
/// "exited normally" restores by itself.
fn mark_clean_exit_in(config_dir: &Path) -> crate::Result<()> {
    for profile_name in active_profile_names(config_dir)? {
        let path = config_dir.join(profile_name).join(PREFERENCES_FILE_NAME);
        if !path.exists() {
            continue;
        }
        let mut root = load_preferences(&path)?;
        merge_json_values(
            &mut root,
            serde_json::json!({ "profile": { "exit_type": "Normal" } }),
        );
        atomic_write(&path, serde_json::to_string(&root)?.as_bytes())?;
    }

    Ok(())
}

fn write_preferences(path: &Path, state: &ThemeState) -> crate::Result<()> {
    // load_preferences guarantees an object root and merge_json_values preserves it.
    let mut root = load_preferences(path)?;
    merge_json_values(&mut root, browser_theme_preferences());
    clear_managed_browser_theme_customizations(&mut root);
    merge_json_values(&mut root, font_preferences(state));
    clear_managed_font_sizes(&mut root);

    atomic_write(path, serde_json::to_string(&root)?.as_bytes())
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
        crate::invalid_data(format!("Invalid JSON in {}: {error}", path.display()))
    })?;

    if !value.is_object() {
        return Err(crate::invalid_data(format!(
            "{}: expected top-level JSON object",
            path.display()
        ))
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
    let mut fonts = Map::new();
    for (family_key, font) in [
        ("standard", &state.system_font),
        ("sansserif", &state.system_font),
        ("serif", &state.system_font),
        ("fixed", &state.mono_font),
    ] {
        let mut script = Map::new();
        script.insert(COMMON_SCRIPT.to_owned(), Value::String(font.clone()));
        fonts.insert(family_key.to_owned(), Value::Object(script));
    }

    serde_json::json!({ "webkit": { "webprefs": { "fonts": fonts } } })
}

fn browser_theme_preferences() -> Value {
    serde_json::json!({
        "browser": {
            "theme": {
                "color_scheme2": COLOR_SCHEME_DEVICE,
            }
        }
    })
}

fn clear_managed_browser_theme_customizations(root: &mut Value) {
    let Some(theme) = root
        .get_mut("browser")
        .and_then(Value::as_object_mut)
        .and_then(|browser| browser.get_mut("theme"))
        .and_then(Value::as_object_mut)
    else {
        return;
    };

    for key in [
        "color_variant2",
        "user_color2",
        "color_variant",
        "user_color",
    ] {
        theme.remove(key);
    }
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{test_support::TempDir, theme::targets::testsupport::dummy_state};

    fn read_json(path: &Path) -> Value {
        serde_json::from_str(&fs::read_to_string(path).expect("preferences exist"))
            .expect("valid preferences json")
    }

    #[test]
    fn write_preferences_creates_webkit_font_settings() {
        let dir = TempDir::new("helium-fonts-create").expect("temp dir");
        let path = dir.path().join("Preferences");
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
        assert_eq!(
            written["browser"]["theme"]["color_scheme2"],
            Value::from(COLOR_SCHEME_DEVICE)
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
    }

    #[test]
    fn write_active_preferences_updates_all_safe_active_profiles_and_ignores_invalid() {
        let dir = TempDir::new("helium-active-profiles").expect("temp dir");
        fs::write(
            dir.path().join(LOCAL_STATE_FILE_NAME),
            r#"{"profile":{"last_active_profiles":["Profile 1","../escape","Profile 1","Profile 2"]}}"#,
        )
        .expect("local state written");

        write_active_preferences(dir.path(), &dummy_state()).expect("write succeeds");

        assert!(
            dir.path()
                .join("Profile 1")
                .join(PREFERENCES_FILE_NAME)
                .exists()
        );
        assert!(
            dir.path()
                .join("Profile 2")
                .join(PREFERENCES_FILE_NAME)
                .exists()
        );
        assert!(
            !dir.path()
                .join(DEFAULT_PROFILE_NAME)
                .join(PREFERENCES_FILE_NAME)
                .exists()
        );
        assert!(
            !dir.path()
                .parent()
                .expect("has parent")
                .join("escape")
                .join(PREFERENCES_FILE_NAME)
                .exists()
        );

        let fallback = TempDir::new("helium-active-fallback").expect("temp dir");
        fs::write(fallback.path().join(LOCAL_STATE_FILE_NAME), "not json")
            .expect("local state written");
        write_active_preferences(fallback.path(), &dummy_state()).expect("write succeeds");
        assert!(
            fallback
                .path()
                .join(DEFAULT_PROFILE_NAME)
                .join(PREFERENCES_FILE_NAME)
                .exists()
        );
    }

    #[test]
    fn mark_clean_exit_touches_only_the_exit_type() {
        let dir = TempDir::new("helium-clean-exit").expect("temp dir");
        let profile = dir.path().join(DEFAULT_PROFILE_NAME);
        fs::create_dir_all(&profile).expect("create profile dir");
        let path = profile.join(PREFERENCES_FILE_NAME);
        fs::write(
            &path,
            r#"{"profile":{"exit_type":"Crashed","name":"Kevin"},"session":{"restore_on_startup":1}}"#,
        )
        .expect("write preferences");

        mark_clean_exit_in(dir.path()).expect("mark clean exit");

        assert_eq!(
            read_json(&path),
            serde_json::json!({
                "profile": { "exit_type": "Normal", "name": "Kevin" },
                "session": { "restore_on_startup": 1 },
            })
        );
    }

    #[test]
    fn write_preferences_preserves_unmanaged_keys_and_clears_managed_overrides() {
        let dir = TempDir::new("helium-fonts-merge").expect("temp dir");
        let path = dir.path().join("Preferences");
        fs::write(
            &path,
            r#"{"browser":{"show_home_button":true,"theme":{"color_scheme2":2,"color_variant2":2,"user_color2":-7558172}},"webkit":{"webprefs":{"javascript_enabled":true,"default_font_size":22,"default_fixed_font_size":18}}}"#,
        )
        .expect("fixture written");

        write_preferences(&path, &dummy_state()).expect("write succeeds");
        let written = read_json(&path);

        assert_eq!(written["browser"]["show_home_button"], Value::Bool(true));
        assert_eq!(
            written["browser"]["theme"]["color_scheme2"],
            Value::from(COLOR_SCHEME_DEVICE)
        );
        assert!(written["browser"]["theme"].get("color_variant2").is_none());
        assert!(written["browser"]["theme"].get("user_color2").is_none());
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
    }
}
