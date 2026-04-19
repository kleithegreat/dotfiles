use super::{Assembly, GeneratedContent, TargetMetadata};
use crate::theme::{
    atomic_write, expand_user_path, json,
    schema::{ColorScheme, ThemeState},
};
use serde_json::{Map, Value};
use std::path::Path;

pub const METADATA: TargetMetadata = TargetMetadata {
    name: "opencode",
    assembly: Assembly::Concat,
    output_path: Some("~/.config/opencode/tui.json"),
    base_path: Some("config/opencode/base.json"),
    extra_outputs: &[],
    managed_paths: &["~/.config/opencode/themes/desktopctl.json"],
    reload_cmd: None,
    comment: None,
    sync_safe: true,
};

const THEME_NAME: &str = "desktopctl";
const THEME_OUTPUT_PATH: &str = "~/.config/opencode/themes/desktopctl.json";
const THEME_SCHEMA_URL: &str = "https://opencode.ai/theme.json";

pub fn generate(_colors: &ColorScheme, _state: &ThemeState) -> crate::Result<GeneratedContent> {
    let mut root = Map::new();
    root.insert("theme".to_owned(), Value::String(THEME_NAME.to_owned()));

    Ok(GeneratedContent::text(json::format_pretty_value(
        &Value::Object(root),
    )))
}

pub fn persist(colors: &ColorScheme, _state: &ThemeState) -> crate::Result<()> {
    write_theme(&expand_user_path(THEME_OUTPUT_PATH)?, colors)
}

fn write_theme(path: &Path, colors: &ColorScheme) -> crate::Result<()> {
    atomic_write(path, render_theme(colors).as_bytes())
}

fn render_theme(colors: &ColorScheme) -> String {
    let diff_alpha = if colors.is_dark() { 0.18 } else { 0.10 };
    let diff_line_alpha = if colors.is_dark() { 0.24 } else { 0.14 };

    let mut theme = Map::new();
    theme.insert("primary".to_owned(), Value::String(colors.accent.clone()));
    theme.insert("secondary".to_owned(), Value::String(colors.purple.clone()));
    theme.insert("accent".to_owned(), Value::String(colors.blue.clone()));
    theme.insert("error".to_owned(), Value::String(colors.red.clone()));
    theme.insert("warning".to_owned(), Value::String(colors.yellow.clone()));
    theme.insert("success".to_owned(), Value::String(colors.green.clone()));
    theme.insert("info".to_owned(), Value::String(colors.cyan.clone()));
    theme.insert("text".to_owned(), Value::String(colors.fg.clone()));
    theme.insert("textMuted".to_owned(), Value::String(colors.fg3.clone()));
    theme.insert("background".to_owned(), Value::String(colors.bg.clone()));
    theme.insert(
        "backgroundPanel".to_owned(),
        Value::String(colors.bg1.clone()),
    );
    theme.insert(
        "backgroundElement".to_owned(),
        Value::String(colors.bg2.clone()),
    );
    theme.insert("border".to_owned(), Value::String(colors.bg3.clone()));
    theme.insert(
        "borderActive".to_owned(),
        Value::String(colors.accent.clone()),
    );
    theme.insert("borderSubtle".to_owned(), Value::String(colors.bg2.clone()));
    theme.insert("diffAdded".to_owned(), Value::String(colors.green.clone()));
    theme.insert("diffRemoved".to_owned(), Value::String(colors.red.clone()));
    theme.insert("diffContext".to_owned(), Value::String(colors.fg4.clone()));
    theme.insert(
        "diffHunkHeader".to_owned(),
        Value::String(colors.blue.clone()),
    );
    theme.insert(
        "diffHighlightAdded".to_owned(),
        Value::String(colors.green_bright.clone()),
    );
    theme.insert(
        "diffHighlightRemoved".to_owned(),
        Value::String(colors.red_bright.clone()),
    );
    theme.insert(
        "diffAddedBg".to_owned(),
        Value::String(blend_hex(&colors.bg, &colors.green, diff_alpha)),
    );
    theme.insert(
        "diffRemovedBg".to_owned(),
        Value::String(blend_hex(&colors.bg, &colors.red, diff_alpha)),
    );
    theme.insert(
        "diffContextBg".to_owned(),
        Value::String(colors.bg1.clone()),
    );
    theme.insert(
        "diffLineNumber".to_owned(),
        Value::String(colors.fg4.clone()),
    );
    theme.insert(
        "diffAddedLineNumberBg".to_owned(),
        Value::String(blend_hex(&colors.bg1, &colors.green, diff_line_alpha)),
    );
    theme.insert(
        "diffRemovedLineNumberBg".to_owned(),
        Value::String(blend_hex(&colors.bg1, &colors.red, diff_line_alpha)),
    );
    theme.insert("markdownText".to_owned(), Value::String(colors.fg.clone()));
    theme.insert(
        "markdownHeading".to_owned(),
        Value::String(colors.accent.clone()),
    );
    theme.insert(
        "markdownLink".to_owned(),
        Value::String(colors.blue.clone()),
    );
    theme.insert(
        "markdownLinkText".to_owned(),
        Value::String(colors.cyan.clone()),
    );
    theme.insert(
        "markdownCode".to_owned(),
        Value::String(colors.green.clone()),
    );
    theme.insert(
        "markdownBlockQuote".to_owned(),
        Value::String(colors.yellow.clone()),
    );
    theme.insert(
        "markdownEmph".to_owned(),
        Value::String(colors.orange.clone()),
    );
    theme.insert(
        "markdownStrong".to_owned(),
        Value::String(colors.fg.clone()),
    );
    theme.insert(
        "markdownHorizontalRule".to_owned(),
        Value::String(colors.bg3.clone()),
    );
    theme.insert(
        "markdownListItem".to_owned(),
        Value::String(colors.blue.clone()),
    );
    theme.insert(
        "markdownListEnumeration".to_owned(),
        Value::String(colors.cyan.clone()),
    );
    theme.insert(
        "markdownImage".to_owned(),
        Value::String(colors.blue.clone()),
    );
    theme.insert(
        "markdownImageText".to_owned(),
        Value::String(colors.cyan.clone()),
    );
    theme.insert(
        "markdownCodeBlock".to_owned(),
        Value::String(colors.fg.clone()),
    );
    theme.insert(
        "syntaxComment".to_owned(),
        Value::String(colors.fg4.clone()),
    );
    theme.insert(
        "syntaxKeyword".to_owned(),
        Value::String(colors.purple.clone()),
    );
    theme.insert(
        "syntaxFunction".to_owned(),
        Value::String(colors.blue.clone()),
    );
    theme.insert(
        "syntaxVariable".to_owned(),
        Value::String(colors.fg.clone()),
    );
    theme.insert(
        "syntaxString".to_owned(),
        Value::String(colors.green.clone()),
    );
    theme.insert(
        "syntaxNumber".to_owned(),
        Value::String(colors.orange.clone()),
    );
    theme.insert("syntaxType".to_owned(), Value::String(colors.cyan.clone()));
    theme.insert(
        "syntaxOperator".to_owned(),
        Value::String(colors.accent.clone()),
    );
    theme.insert(
        "syntaxPunctuation".to_owned(),
        Value::String(colors.fg2.clone()),
    );

    let mut root = Map::new();
    root.insert(
        "$schema".to_owned(),
        Value::String(THEME_SCHEMA_URL.to_owned()),
    );
    root.insert("theme".to_owned(), Value::Object(theme));

    format!("{}\n", json::format_pretty_value(&Value::Object(root)))
}

fn blend_hex(base: &str, overlay: &str, alpha: f64) -> String {
    let (base_r, base_g, base_b) = parse_hex(base);
    let (overlay_r, overlay_g, overlay_b) = parse_hex(overlay);
    format!(
        "#{:02x}{:02x}{:02x}",
        blend_channel(base_r, overlay_r, alpha),
        blend_channel(base_g, overlay_g, alpha),
        blend_channel(base_b, overlay_b, alpha),
    )
}

fn parse_hex(value: &str) -> (u8, u8, u8) {
    (
        u8::from_str_radix(&value[1..3], 16).expect("validated red channel"),
        u8::from_str_radix(&value[3..5], 16).expect("validated green channel"),
        u8::from_str_radix(&value[5..7], 16).expect("validated blue channel"),
    )
}

fn blend_channel(base: u8, overlay: u8, alpha: f64) -> u8 {
    ((base as f64) + ((overlay as f64) - (base as f64)) * alpha).round() as u8
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::theme::targets::testsupport::{dummy_colors, rose_pine_dawn_colors};
    use std::{
        fs,
        time::{SystemTime, UNIX_EPOCH},
    };

    fn temp_path(name: &str) -> std::path::PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("time works")
            .as_nanos();
        std::env::temp_dir().join(format!("desktopctl-{name}-{nanos}.json"))
    }

    #[test]
    fn theme_file_matches_expected_shape() {
        let rendered = render_theme(&dummy_colors());
        let value: Value = serde_json::from_str(&rendered).expect("valid json");

        assert_eq!(value["$schema"], Value::String(THEME_SCHEMA_URL.to_owned()));
        assert_eq!(
            value["theme"]["background"],
            Value::String("#000000".to_owned())
        );
        assert_eq!(
            value["theme"]["primary"],
            Value::String("#3366ff".to_owned())
        );
        assert_eq!(
            value["theme"]["diffAddedBg"],
            Value::String("#002e00".to_owned())
        );
        assert_eq!(
            value["theme"]["diffRemovedLineNumberBg"],
            Value::String("#3f0202".to_owned())
        );
    }

    #[test]
    fn theme_file_uses_ascii_json_escaping() {
        let rendered = render_theme(&rose_pine_dawn_colors());
        assert!(rendered.is_ascii(), "{rendered}");
    }

    #[test]
    fn write_theme_replaces_output_atomically() {
        let path = temp_path("opencode-theme-write");
        fs::write(&path, "stale").expect("fixture written");

        write_theme(&path, &dummy_colors()).expect("write succeeds");
        let value: Value = serde_json::from_str(&fs::read_to_string(&path).expect("theme exists"))
            .expect("valid theme json");

        assert_eq!(
            value["theme"]["syntaxKeyword"],
            Value::String("#ff00ff".to_owned())
        );

        let _ = fs::remove_file(path);
    }
}
