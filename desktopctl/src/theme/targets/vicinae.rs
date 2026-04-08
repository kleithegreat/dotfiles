use super::{Assembly, GeneratedContent, TargetMetadata};
use crate::theme::{
    json,
    schema::{ColorScheme, ThemeState},
};
use serde_json::{Map, Value};

pub const METADATA: TargetMetadata = TargetMetadata {
    name: "vicinae",
    assembly: Assembly::Concat,
    output_path: Some("~/.config/vicinae/settings.json"),
    base_path: Some("config/vicinae/base.json"),
    extra_outputs: &[],
    reload_cmd: None,
    comment: None,
    sync_safe: true,
};

pub fn generate(colors: &ColorScheme, state: &ThemeState) -> crate::Result<GeneratedContent> {
    let mut font = Map::new();
    let mut normal = Map::new();
    normal.insert(
        "family".to_owned(),
        Value::String(state.system_font.clone()),
    );
    font.insert("normal".to_owned(), Value::Object(normal));

    let mut dark = Map::new();
    dark.insert(
        "name".to_owned(),
        Value::String(colors.vicinae_theme_name()),
    );

    let mut light = Map::new();
    light.insert(
        "name".to_owned(),
        Value::String(colors.vicinae_light_theme_name()),
    );

    let mut theme = Map::new();
    theme.insert("dark".to_owned(), Value::Object(dark));
    theme.insert("light".to_owned(), Value::Object(light));

    let mut root = Map::new();
    root.insert("font".to_owned(), Value::Object(font));
    root.insert("theme".to_owned(), Value::Object(theme));

    Ok(GeneratedContent::text(json::format_pretty_value(
        &Value::Object(root),
    )))
}
