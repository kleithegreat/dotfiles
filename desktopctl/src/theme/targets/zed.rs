use super::{Assembly, GeneratedContent, TargetMetadata};
use crate::theme::{
    json,
    schema::{ColorScheme, ThemeState},
};
use serde_json::{Map, Value};

pub const METADATA: TargetMetadata = TargetMetadata::new(
    "zed",
    Assembly::Concat,
    &[
        "color_scheme",
        "system_font",
        "mono_font",
        "font_size",
        "mono_font_size",
        "zed_mono_font_size_offset",
    ],
)
.output("~/.config/zed/settings.json")
.base("config/zed/base.json");

pub fn generate(colors: &ColorScheme, state: &ThemeState) -> crate::Result<GeneratedContent> {
    let buffer_font_size = state.mono_font_size_for(METADATA.name)?;

    let mut root = Map::new();
    root.insert("theme".to_owned(), Value::String(colors.zed_theme_name()));
    root.insert(
        "buffer_font_family".to_owned(),
        Value::String(state.mono_font.clone()),
    );
    root.insert("buffer_font_size".to_owned(), Value::from(buffer_font_size));
    root.insert(
        "ui_font_family".to_owned(),
        Value::String(state.system_font.clone()),
    );
    root.insert("ui_font_size".to_owned(), Value::from(state.font_size));

    Ok(GeneratedContent::text(json::format_pretty_value(
        &Value::Object(root),
    )))
}
