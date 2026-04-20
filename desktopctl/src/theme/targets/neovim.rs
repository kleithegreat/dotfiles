use super::{Assembly, GeneratedContent, TargetMetadata};
use crate::theme::{
    json,
    schema::{ColorScheme, ThemeState},
};
use serde_json::{Map, Value};

pub const METADATA: TargetMetadata = TargetMetadata {
    name: "neovim",
    assembly: Assembly::Standalone,
    output_path: Some("~/.config/nvim/lua/theme-state.json"),
    base_path: None,
    extra_outputs: &[],
    managed_paths: &[],
    state_keys: &["color_scheme"],
    reload_cmd: None,
    comment: None,
    sync_safe: true,
};

pub fn generate(colors: &ColorScheme, _state: &ThemeState) -> crate::Result<GeneratedContent> {
    let mut value = Map::new();
    value.insert(
        "colorscheme".to_owned(),
        Value::String(colors.family.clone()),
    );
    value.insert(
        "background".to_owned(),
        Value::String(colors.variant.clone()),
    );

    Ok(GeneratedContent::text(format!(
        "{}\n",
        json::format_pretty_value(&Value::Object(value))
    )))
}
