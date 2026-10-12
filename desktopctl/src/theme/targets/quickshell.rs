use super::Target;
use crate::theme::{
    json,
    schema::{ColorScheme, ThemeState},
};

pub const TARGET: Target = Target::standalone(
    "quickshell",
    &[
        "color_scheme",
        "system_font",
        "mono_font",
        "font_size",
        "quickshell_font_size_offset",
    ],
    "~/.config/quickshell/GeneratedTheme.json",
    generate,
);

/// Exactly the keys `config/quickshell/Theme.qml` reads.
pub fn generate(colors: &ColorScheme, state: &ThemeState) -> crate::Result<String> {
    let theme = serde_json::json!({
        "colors": {
            "bg": colors.bg,
            "bg1": colors.bg1,
            "fg": colors.fg,
            "fg2": colors.fg2,
            "fg3": colors.fg3,
            "fg4": colors.fg4,
            "redBright": colors.red_bright,
            "greenBright": colors.green_bright,
            "yellowBright": colors.yellow_bright,
            "accent": colors.accent,
        },
        "fonts": {
            "family": state.mono_font,
            "systemFamily": state.system_font,
            "size": state.font_size_for(TARGET.name)?.max(1),
        },
    });

    Ok(format!("{}\n", json::format_pretty_value(&theme)))
}
