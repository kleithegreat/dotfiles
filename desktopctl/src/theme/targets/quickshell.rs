use super::{Assembly, GeneratedContent, TargetMetadata};
use crate::theme::{
    json,
    schema::{ColorScheme, ThemeState},
};
use serde_json::{Map, Value};

pub const METADATA: TargetMetadata = TargetMetadata {
    name: "quickshell",
    assembly: Assembly::Standalone,
    output_path: Some("~/.config/quickshell/GeneratedTheme.json"),
    base_path: None,
    extra_outputs: &[],
    managed_paths: &[],
    reload_cmd: None,
    comment: None,
    sync_safe: true,
};

pub fn generate(colors: &ColorScheme, state: &ThemeState) -> crate::Result<GeneratedContent> {
    let font_size = state.font_size_for("quickshell")?.max(1);
    let font_size_small = (font_size - 2).max(1);
    let font_size_large = font_size + 2;

    let mut theme = Map::new();

    let mut color_map = Map::new();
    color_map.insert("bg".to_owned(), Value::String(colors.bg.clone()));
    color_map.insert("bg0_h".to_owned(), Value::String(colors.bg_dim.clone()));
    color_map.insert("bg1".to_owned(), Value::String(colors.bg1.clone()));
    color_map.insert("bg2".to_owned(), Value::String(colors.bg2.clone()));
    color_map.insert("bg3".to_owned(), Value::String(colors.bg3.clone()));
    color_map.insert("fg".to_owned(), Value::String(colors.fg.clone()));
    color_map.insert("fg2".to_owned(), Value::String(colors.fg2.clone()));
    color_map.insert("fg3".to_owned(), Value::String(colors.fg3.clone()));
    color_map.insert("fg4".to_owned(), Value::String(colors.fg4.clone()));
    color_map.insert("red".to_owned(), Value::String(colors.red.clone()));
    color_map.insert("green".to_owned(), Value::String(colors.green.clone()));
    color_map.insert("yellow".to_owned(), Value::String(colors.yellow.clone()));
    color_map.insert("blue".to_owned(), Value::String(colors.blue.clone()));
    color_map.insert("purple".to_owned(), Value::String(colors.purple.clone()));
    color_map.insert("aqua".to_owned(), Value::String(colors.cyan.clone()));
    color_map.insert("orange".to_owned(), Value::String(colors.orange.clone()));
    color_map.insert(
        "redBright".to_owned(),
        Value::String(colors.red_bright.clone()),
    );
    color_map.insert(
        "greenBright".to_owned(),
        Value::String(colors.green_bright.clone()),
    );
    color_map.insert(
        "yellowBright".to_owned(),
        Value::String(colors.yellow_bright.clone()),
    );
    color_map.insert(
        "blueBright".to_owned(),
        Value::String(colors.blue_bright.clone()),
    );
    color_map.insert(
        "purpleBright".to_owned(),
        Value::String(colors.purple_bright.clone()),
    );
    color_map.insert(
        "aquaBright".to_owned(),
        Value::String(colors.cyan_bright.clone()),
    );
    color_map.insert(
        "orangeBright".to_owned(),
        Value::String(colors.orange_bright.clone()),
    );
    color_map.insert("accent".to_owned(), Value::String(colors.accent.clone()));

    let mut font_map = Map::new();
    font_map.insert("family".to_owned(), Value::String(state.mono_font.clone()));
    font_map.insert(
        "systemFamily".to_owned(),
        Value::String(state.system_font.clone()),
    );
    font_map.insert("size".to_owned(), Value::from(font_size));
    font_map.insert("sizeSmall".to_owned(), Value::from(font_size_small));
    font_map.insert("sizeLarge".to_owned(), Value::from(font_size_large));

    theme.insert("colors".to_owned(), Value::Object(color_map));
    theme.insert("fonts".to_owned(), Value::Object(font_map));

    Ok(GeneratedContent::text(format!(
        "{}\n",
        json::format_pretty_value(&Value::Object(theme))
    )))
}
