use super::{Assembly, GeneratedContent, TargetMetadata};
use crate::theme::schema::{ColorScheme, ThemeState};

pub const METADATA: TargetMetadata =
    TargetMetadata::new("zathura", Assembly::Import, &["color_scheme"])
        .output("~/.config/zathura/colors")
        .comment("#");

pub fn generate(colors: &ColorScheme, _state: &ThemeState) -> crate::Result<GeneratedContent> {
    Ok(GeneratedContent::text(format!(
        concat!(
            "set default-bg \"{}\"\n",
            "set default-fg \"{}\"\n",
            "set statusbar-bg \"{}\"\n",
            "set statusbar-fg \"{}\"\n",
            "set inputbar-bg \"{}\"\n",
            "set inputbar-fg \"{}\"\n",
            "set notification-bg \"{}\"\n",
            "set notification-fg \"{}\"\n",
            "set notification-error-bg \"{}\"\n",
            "set notification-error-fg \"{}\"\n",
            "set notification-warning-bg \"{}\"\n",
            "set notification-warning-fg \"{}\"\n",
            "set highlight-color \"{}\"\n",
            "set highlight-active-color \"{}\"\n",
            "set completion-bg \"{}\"\n",
            "set completion-fg \"{}\"\n",
            "set completion-highlight-bg \"{}\"\n",
            "set completion-highlight-fg \"{}\"\n",
            "set recolor-lightcolor \"{}\"\n",
            "set recolor-darkcolor \"{}\"\n",
            "set recolor \"true\"\n",
            "set recolor-keephue \"false\"\n",
        ),
        colors.bg,
        colors.fg,
        colors.bg1,
        colors.fg,
        colors.bg,
        colors.fg,
        colors.bg1,
        colors.fg,
        colors.red,
        colors.fg,
        colors.yellow,
        colors.bg,
        colors.yellow,
        colors.accent,
        colors.bg1,
        colors.fg,
        colors.accent,
        colors.bg,
        colors.bg,
        colors.fg,
    )))
}
