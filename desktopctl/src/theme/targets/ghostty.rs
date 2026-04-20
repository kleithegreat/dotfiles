use super::{Assembly, GeneratedContent, TargetMetadata};
use crate::theme::schema::{ColorScheme, ThemeState};

pub const METADATA: TargetMetadata = TargetMetadata::new(
    "ghostty",
    Assembly::Import,
    &[
        "color_scheme",
        "mono_font",
        "mono_font_size",
        "ghostty_mono_font_size_offset",
    ],
)
.output("~/.config/ghostty/theme.conf")
.comment("#");

pub fn generate(colors: &ColorScheme, state: &ThemeState) -> crate::Result<GeneratedContent> {
    let mut lines = vec![
        format!("font-family = {}", state.mono_font),
        format!("font-size = {}", state.mono_font_size_for(METADATA.name)?),
        format!("background = {}", colors.bg),
        format!("foreground = {}", colors.fg),
        format!("selection-background = {}", colors.bg3),
        format!("selection-foreground = {}", colors.fg),
        format!("cursor-color = {}", colors.fg),
        format!("cursor-text = {}", colors.bg),
    ];
    for (index, color) in colors.palette.iter().enumerate() {
        lines.push(format!("palette = {index}={color}"));
    }
    Ok(GeneratedContent::text(format!("{}\n", lines.join("\n"))))
}
