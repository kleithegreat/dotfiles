use super::{Assembly, GeneratedContent, TargetMetadata};
use crate::theme::schema::{ColorScheme, ThemeState};

pub const METADATA: TargetMetadata =
    TargetMetadata::new("bat", Assembly::Standalone, &["color_scheme"])
        .output("~/.config/bat/config");

pub fn generate(colors: &ColorScheme, _state: &ThemeState) -> crate::Result<GeneratedContent> {
    // bat splits config lines shell-style; half the bundled theme names hold a space.
    Ok(GeneratedContent::text(format!(
        "--theme=\"{}\"\n",
        colors.bat_theme_name()
    )))
}
