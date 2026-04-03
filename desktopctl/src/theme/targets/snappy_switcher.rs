use super::{Assembly, GeneratedContent, TargetMetadata};
use crate::theme::{
    find_command,
    schema::{ColorScheme, ThemeState},
};
use std::{
    env,
    process::{Command, Stdio},
};

pub const METADATA: TargetMetadata = TargetMetadata {
    name: "snappy_switcher",
    assembly: Assembly::Concat,
    output_path: Some("~/.config/snappy-switcher/config.ini"),
    base_path: Some("~/repos/dotfiles/config/snappy-switcher/base.ini"),
    extra_outputs: &[],
    reload_cmd: None,
    comment: Some("#"),
    sync_safe: true,
};

fn rgba(hex_color: &str, alpha: &str) -> String {
    format!("{hex_color}{alpha}")
}

fn theme_name(state: &ThemeState, colors: &ColorScheme) -> &'static str {
    match state.color_scheme.as_str() {
        "catppuccin-frappe" => "catppuccin-mocha.ini",
        "catppuccin-latte" => "catppuccin-latte.ini",
        "catppuccin-macchiato" => "catppuccin-mocha.ini",
        "catppuccin-mocha" => "catppuccin-mocha.ini",
        "gruvbox-dark" => "gruvbox-dark.ini",
        "nord" => "nord.ini",
        "nord-light" => "catppuccin-latte.ini",
        "rose-pine" => "rose-pine.ini",
        "rose-pine-dawn" => "catppuccin-latte.ini",
        "solarized-dark" => "snappy-slate.ini",
        "solarized-light" => "catppuccin-latte.ini",
        "tokyo-night" => "tokyo-night.ini",
        "tokyo-night-light" => "catppuccin-latte.ini",
        _ if colors.variant == "light" => "catppuccin-latte.ini",
        _ => "snappy-slate.ini",
    }
}

pub fn generate(colors: &ColorScheme, state: &ThemeState) -> crate::Result<GeneratedContent> {
    let title_size = (state.font_size - 1).max(1);
    Ok(GeneratedContent::text(format!(
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
            "workspace_color = {}\n",
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
        theme_name(state, colors),
        rgba(&colors.bg, "ff"),
        rgba(&colors.bg1, "ff"),
        rgba(&colors.bg2, "ff"),
        rgba(&colors.fg, "ff"),
        rgba(&colors.fg4, "ff"),
        rgba(&colors.accent, "ff"),
        rgba(&colors.bg1, "cc"),
        rgba(&colors.accent, "ff"),
        rgba(&colors.bg, "ff"),
        rgba(&colors.fg, "ff"),
        state.icon_theme,
        state.system_font,
        title_size,
    )))
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
