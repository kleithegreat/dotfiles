use super::{Assembly, GeneratedContent, TargetMetadata};
use crate::theme::{
    json,
    schema::{ColorScheme, ColorSchemeAppearance, ThemeState},
};
use serde_json::{Map, Value};

pub const METADATA: TargetMetadata =
    TargetMetadata::new("neovim", Assembly::Standalone, &["color_scheme"])
        .output("~/.config/nvim/lua/theme-state.json");

pub fn generate(colors: &ColorScheme, _state: &ThemeState) -> crate::Result<GeneratedContent> {
    let mut value = Map::new();
    value.insert(
        "background".to_owned(),
        Value::String(
            match colors.appearance {
                ColorSchemeAppearance::Dark => "dark",
                ColorSchemeAppearance::Light => "light",
            }
            .to_owned(),
        ),
    );

    Ok(GeneratedContent::text(format!(
        "{}\n",
        json::format_pretty_value(&Value::Object(value))
    )))
}
