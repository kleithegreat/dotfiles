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
    base_path: Some("~/repos/dotfiles/config/vicinae/base.json"),
    extra_outputs: &[],
    reload_cmd: None,
    comment: None,
    sync_safe: true,
};

fn resolve_theme(family: &str, variant: &str) -> String {
    match (family, variant) {
        ("gruvbox", "dark") => "gruvbox-dark".to_owned(),
        ("gruvbox", "light") => "gruvbox-light".to_owned(),
        ("solarized", "dark") => "solarized-dark".to_owned(),
        ("solarized", "light") => "solarized-light".to_owned(),
        ("catppuccin", "mocha") => "catppuccin-mocha".to_owned(),
        ("catppuccin", "latte") => "catppuccin-latte".to_owned(),
        ("catppuccin", "frappe") => "catppuccin-frappe".to_owned(),
        ("catppuccin", "macchiato") => "catppuccin-macchiato".to_owned(),
        ("nord", "dark") => "nord".to_owned(),
        ("dracula", "dark") => "dracula".to_owned(),
        ("rose-pine", "dark") => "rose-pine".to_owned(),
        ("rose-pine", "light") => "rose-pine-dawn".to_owned(),
        ("tokyo-night", "dark") => "tokyo-night".to_owned(),
        _ => format!("{family}-{variant}"),
    }
}

pub fn generate(colors: &ColorScheme, state: &ThemeState) -> crate::Result<GeneratedContent> {
    let theme_name = resolve_theme(&colors.family, &colors.variant);

    let mut font = Map::new();
    let mut normal = Map::new();
    normal.insert(
        "family".to_owned(),
        Value::String(state.system_font.clone()),
    );
    font.insert("normal".to_owned(), Value::Object(normal));

    let mut dark = Map::new();
    dark.insert("name".to_owned(), Value::String(theme_name));

    let mut light = Map::new();
    light.insert(
        "name".to_owned(),
        Value::String(resolve_theme(&colors.family, "light")),
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
