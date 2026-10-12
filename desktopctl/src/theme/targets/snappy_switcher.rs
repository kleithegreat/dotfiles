use super::Target;
use crate::theme::{
    command::find_command,
    schema::{ColorScheme, ThemeState},
};
use std::{
    env,
    process::{Command, Stdio},
};

pub const TARGET: Target = Target::concat(
    "snappy_switcher",
    &["color_scheme", "system_font", "icon_theme", "font_size"],
    "~/.config/snappy-switcher/config.ini",
    "bases/snappy-switcher.ini",
    generate,
)
.comment("#")
.on_apply(on_apply);

fn rgba(hex_color: &str, alpha: &str) -> String {
    format!("{hex_color}{alpha}")
}

pub fn generate(colors: &ColorScheme, state: &ThemeState) -> crate::Result<String> {
    let title_size = (state.font_size - 1).max(1);
    Ok(format!(
        concat!(
            "[theme]\n",
            "name = {}\n",
            "background = {}\n",
            "card_bg = {}\n",
            "card_selected = {}\n",
            "text_color = {}\n",
            "subtext_color = {}\n",
            "border_color = {}\n",
            "bundle_bg = {}\n",
            "badge_bg = {}\n",
            "badge_text_color = {}\n",
            "border_width = 2\n",
            "corner_radius = 12\n",
            "\n",
            "[icons]\n",
            "theme = {}\n",
            "fallback = Adwaita\n",
            "\n",
            "[font]\n",
            "family = {}\n",
            "weight = Bold\n",
            "title_size = {}\n",
        ),
        colors.app_themes.snappy_switcher,
        rgba(&colors.bg, "ff"),
        rgba(&colors.bg1, "ff"),
        rgba(&colors.bg2, "ff"),
        rgba(&colors.fg, "ff"),
        rgba(&colors.fg4, "ff"),
        rgba(&colors.accent, "ff"),
        rgba(&colors.bg1, "cc"),
        rgba(&colors.accent, "ff"),
        rgba(&colors.bg, "ff"),
        state.icon_theme,
        state.system_font,
        title_size,
    ))
}

pub fn on_apply(_colors: &ColorScheme, _state: &ThemeState) -> crate::Result<()> {
    if env::var_os("WAYLAND_DISPLAY").is_none() {
        return Ok(());
    }

    let Some(snappy) = find_command("snappy-switcher") else {
        return Ok(());
    };

    let devnull = Stdio::null();
    let _ = Command::new(&snappy)
        .arg("quit")
        .stdout(devnull)
        .stderr(Stdio::null())
        .status();

    let _child = Command::new(snappy)
        .arg("--daemon")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()?;

    Ok(())
}
