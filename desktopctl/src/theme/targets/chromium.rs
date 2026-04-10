use super::{Assembly, GeneratedContent, TargetMetadata};
use crate::theme::{
    atomic_write, expand_user_path, json,
    schema::{ColorScheme, ThemeState},
};
use serde_json::{Map, Value};
use std::{fs, io, path::Path};

pub const METADATA: TargetMetadata = TargetMetadata {
    name: "chromium",
    assembly: Assembly::Command,
    output_path: None,
    base_path: None,
    extra_outputs: &[],
    reload_cmd: None,
    comment: None,
    sync_safe: true,
};

const PREFERENCES_PATH: &str = "~/.config/chromium/Default/Preferences";
const COMMON_SCRIPT: &str = "Zyyy";
const CSS_PIXELS_PER_POINT: f64 = 96.0 / 72.0;

pub fn generate(_colors: &ColorScheme, _state: &ThemeState) -> crate::Result<GeneratedContent> {
    Ok(GeneratedContent::commands(Vec::new()))
}

pub fn persist(_colors: &ColorScheme, state: &ThemeState) -> crate::Result<()> {
    write_preferences(&expand_user_path(PREFERENCES_PATH)?, state)
}

fn write_preferences(path: &Path, state: &ThemeState) -> crate::Result<()> {
    let mut root = load_preferences(path)?;
    merge_value(&mut root, font_preferences(state)?);

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

fn font_preferences(state: &ThemeState) -> crate::Result<Value> {
    let font_size = chromium_font_pixels(state.font_size_for(METADATA.name)?);
    let fixed_font_size = chromium_font_pixels(state.mono_font_size);

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
    webprefs.insert("default_font_size".to_owned(), Value::from(font_size));
    webprefs.insert(
        "default_fixed_font_size".to_owned(),
        Value::from(fixed_font_size),
    );

    let mut webkit = Map::new();
    webkit.insert("webprefs".to_owned(), Value::Object(webprefs));

    let mut root = Map::new();
    root.insert("webkit".to_owned(), Value::Object(webkit));
    Ok(Value::Object(root))
}

fn chromium_font_pixels(point_size: i64) -> i64 {
    ((point_size as f64) * CSS_PIXELS_PER_POINT).round() as i64
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
        let mut state = dummy_state();
        state.chromium_font_size_offset = 2;

        write_preferences(&path, &state).expect("write succeeds");
        let written = read_json(&path);

        assert_eq!(
            written["webkit"]["webprefs"]["fonts"]["standard"][COMMON_SCRIPT],
            Value::String(state.system_font.clone())
        );
        assert_eq!(
            written["webkit"]["webprefs"]["fonts"]["fixed"][COMMON_SCRIPT],
            Value::String(state.mono_font.clone())
        );
        assert_eq!(
            written["webkit"]["webprefs"]["default_font_size"],
            Value::from(17)
        );
        assert_eq!(
            written["webkit"]["webprefs"]["default_fixed_font_size"],
            Value::from(15)
        );

        let _ = fs::remove_file(path);
    }

    #[test]
    fn write_preferences_preserves_unmanaged_keys() {
        let path = temp_path("chromium-fonts-merge");
        fs::write(
            &path,
            r#"{"browser":{"show_home_button":true},"webkit":{"webprefs":{"javascript_enabled":true}}}"#,
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

        let _ = fs::remove_file(path);
    }

    #[test]
    fn chromium_font_pixels_rounds_point_sizes_to_css_pixels() {
        assert_eq!(chromium_font_pixels(11), 15);
        assert_eq!(chromium_font_pixels(12), 16);
        assert_eq!(chromium_font_pixels(16), 21);
    }
}
