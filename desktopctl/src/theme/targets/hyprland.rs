use super::{Assembly, GeneratedContent, TargetMetadata};
use crate::theme::schema::{ColorScheme, ThemeState};

const RELOAD_CMD: &[&str] = &["hyprctl", "reload"];

pub const METADATA: TargetMetadata = TargetMetadata::new(
    "hyprland",
    Assembly::Standalone,
    &["color_scheme", "mono_font", "system_font"],
)
.output("~/.config/hypr/colors.conf")
.reload_cmd(RELOAD_CMD)
.comment("#");

fn rgb(hex_color: &str) -> String {
    format!("rgb({})", &hex_color[1..])
}

fn rgba(hex_color: &str, alpha: &str) -> String {
    format!("rgba({}{alpha})", &hex_color[1..])
}

pub fn generate(colors: &ColorScheme, state: &ThemeState) -> crate::Result<GeneratedContent> {
    Ok(GeneratedContent::text(format!(
        concat!(
            "$theme_bg       = {}\n",
            "$theme_bg_rgba  = {}\n",
            "$theme_bg_dim   = {}\n",
            "$theme_bg_dim_rgba = {}\n",
            "$theme_bg1      = {}\n",
            "$theme_bg1_rgba = {}\n",
            "$theme_bg2      = {}\n",
            "$theme_bg2_rgba = {}\n",
            "$theme_bg3      = {}\n",
            "$theme_bg3_rgba = {}\n",
            "$theme_fg       = {}\n",
            "$theme_fg_rgba  = {}\n",
            "$theme_accent   = {}\n",
            "$theme_accent_rgba = {}\n",
            "$theme_red      = {}\n",
            "$theme_red_rgba = {}\n",
            "$theme_green    = {}\n",
            "$theme_green_rgba = {}\n",
            "$theme_yellow   = {}\n",
            "$theme_yellow_rgba = {}\n",
            "$theme_blue     = {}\n",
            "$theme_blue_rgba = {}\n",
            "$theme_purple   = {}\n",
            "$theme_purple_rgba = {}\n",
            "$theme_cyan     = {}\n",
            "$theme_cyan_rgba = {}\n",
            "$theme_orange   = {}\n",
            "$theme_orange_rgba = {}\n",
            "$theme_font     = {}\n",
            "$theme_sys_font = {}\n",
        ),
        rgb(&colors.bg),
        rgba(&colors.bg, "ff"),
        rgb(&colors.bg_dim),
        rgba(&colors.bg_dim, "ff"),
        rgb(&colors.bg1),
        rgba(&colors.bg1, "ff"),
        rgb(&colors.bg2),
        rgba(&colors.bg2, "ff"),
        rgb(&colors.bg3),
        rgba(&colors.bg3, "ff"),
        rgb(&colors.fg),
        rgba(&colors.fg, "ff"),
        rgb(&colors.accent),
        rgba(&colors.accent, "ff"),
        rgb(&colors.red),
        rgba(&colors.red, "ff"),
        rgb(&colors.green),
        rgba(&colors.green, "ff"),
        rgb(&colors.yellow),
        rgba(&colors.yellow, "ff"),
        rgb(&colors.blue),
        rgba(&colors.blue, "ff"),
        rgb(&colors.purple),
        rgba(&colors.purple, "ff"),
        rgb(&colors.cyan),
        rgba(&colors.cyan, "ff"),
        rgb(&colors.orange),
        rgba(&colors.orange, "ff"),
        state.mono_font,
        state.system_font,
    )))
}
