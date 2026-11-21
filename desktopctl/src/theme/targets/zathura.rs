use super::Target;
use crate::theme::{
    color::readable_on_ends,
    schema::{ColorScheme, ThemeState},
};

pub const TARGET: Target = Target::standalone(
    "zathura",
    &["color_scheme"],
    "~/.config/zathura/colors",
    generate,
)
.comment("#");

pub fn generate(colors: &ColorScheme, _state: &ThemeState) -> crate::Result<String> {
    let on_red = readable_on_ends(&colors.red, &colors.bg, &colors.fg);
    let on_yellow = readable_on_ends(&colors.yellow, &colors.bg, &colors.fg);
    let on_accent = readable_on_ends(&colors.accent, &colors.bg, &colors.fg);

    Ok(format!(
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
        on_red,
        colors.yellow,
        on_yellow,
        colors.yellow,
        colors.accent,
        colors.bg1,
        colors.fg,
        colors.accent,
        on_accent,
        colors.bg,
        colors.fg,
    ))
}
