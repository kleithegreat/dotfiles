use super::Target;
use crate::theme::{
    json,
    schema::{ColorScheme, ThemeState},
};
use serde_json::{Map, Value};

pub const TARGET: Target = Target::concat(
    "zed",
    &[
        "color_scheme",
        "system_font",
        "mono_font",
        "font_size",
        "mono_font_size",
        "zed_mono_font_size_offset",
    ],
    "~/.config/zed/settings.json",
    "bases/zed.json",
    generate,
);

pub fn generate(colors: &ColorScheme, state: &ThemeState) -> crate::Result<String> {
    let buffer_font_size = state.mono_font_size_for(TARGET.name)?;

    let mut root = Map::new();
    root.insert(
        "theme".to_owned(),
        Value::String(colors.app_themes.zed.clone()),
    );
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

    Ok(json::format_pretty_value(&Value::Object(root)))
}
