use super::Target;
use crate::theme::schema::{ColorScheme, ThemeState};

pub const TARGET: Target = Target::standalone(
    "ghostty",
    &[
        "color_scheme",
        "mono_font",
        "mono_font_size",
        "ghostty_mono_font_size_offset",
    ],
    "~/.config/ghostty/theme.conf",
    generate,
)
.comment("#");

pub fn generate(colors: &ColorScheme, state: &ThemeState) -> crate::Result<String> {
    let mut lines = vec![
        format!("font-family = {}", state.mono_font),
        format!("font-size = {}", state.mono_font_size_for(TARGET.name)?),
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
    Ok(format!("{}\n", lines.join("\n")))
}
