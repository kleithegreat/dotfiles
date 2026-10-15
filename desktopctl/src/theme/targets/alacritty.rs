use super::Target;
use crate::theme::schema::{ColorScheme, ThemeState};

pub const TARGET: Target = Target::standalone(
    "alacritty",
    &[
        "color_scheme",
        "mono_font",
        "mono_font_size",
        "alacritty_mono_font_size_offset",
    ],
    "~/.config/alacritty/theme.toml",
    generate,
)
.comment("#");

pub fn generate(colors: &ColorScheme, state: &ThemeState) -> crate::Result<String> {
    let mut out = format!(
        concat!(
            "[font]\n",
            "normal = {{ family = \"{}\" }}\n",
            "size = {}\n",
            "\n",
            "[colors.primary]\n",
            "background = \"{}\"\n",
            "foreground = \"{}\"\n",
        ),
        state.mono_font,
        state.mono_font_size_for(TARGET.name)?,
        colors.bg,
        colors.fg,
    );
    for (section, offset) in [("normal", 0), ("bright", 8)] {
        out.push_str(&format!("\n[colors.{section}]\n"));
        let names = [
            "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
        ];
        for (index, name) in names.into_iter().enumerate() {
            out.push_str(&format!(
                "{name:<7} = \"{}\"\n",
                colors.palette[offset + index]
            ));
        }
    }
    Ok(out)
}
