use super::{Assembly, GeneratedContent, TargetMetadata};
use crate::theme::schema::{ColorScheme, ThemeState};

pub const METADATA: TargetMetadata = TargetMetadata {
    name: "bat",
    assembly: Assembly::Standalone,
    output_path: Some("~/.config/bat/config"),
    base_path: None,
    extra_outputs: &[],
    reload_cmd: None,
    comment: None,
    sync_safe: true,
};

fn bat_theme_name(colors: &ColorScheme) -> &'static str {
    match (colors.family.as_str(), colors.variant.as_str()) {
        ("gruvbox", "dark") => "gruvbox-dark",
        ("gruvbox", "light") => "gruvbox-light",
        ("solarized", "dark") => "Solarized (dark)",
        ("solarized", "light") => "Solarized (light)",
        ("catppuccin", "mocha") => "Catppuccin Mocha",
        ("catppuccin", "frappe") => "Catppuccin Frappe",
        ("catppuccin", "latte") => "Catppuccin Latte",
        ("catppuccin", "macchiato") => "Catppuccin Macchiato",
        _ => "base16",
    }
}

pub fn generate(colors: &ColorScheme, _state: &ThemeState) -> crate::Result<GeneratedContent> {
    Ok(GeneratedContent::text(format!(
        "--theme={}\n",
        bat_theme_name(colors)
    )))
}
