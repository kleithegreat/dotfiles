use super::Target;
use crate::theme::schema::{ColorScheme, ThemeState};

pub const TARGET: Target =
    Target::standalone("bat", &["color_scheme"], "~/.config/bat/config", generate);

pub fn generate(colors: &ColorScheme, _state: &ThemeState) -> crate::Result<String> {
    // bat splits config lines shell-style; half the bundled theme names hold a space.
    Ok(format!("--theme=\"{}\"\n", colors.app_themes.bat))
}
