use super::{Assembly, GeneratedContent, TargetMetadata};
use crate::theme::{
    expand_user_path, find_command, run_owned_command,
    schema::{ColorScheme, ThemeState},
};
use std::fs;

pub const METADATA: TargetMetadata =
    TargetMetadata::new("spicetify", Assembly::Standalone, &["color_scheme"])
        .output("~/.config/spicetify/Themes/ApplyTheme/color.ini")
        .managed_paths(&["~/.config/spicetify/Themes/ApplyTheme/user.css"])
        .comment(";");

const THEME_DIR: &str = "~/.config/spicetify/Themes/ApplyTheme";
const USER_CSS_PATH: &str = "~/.config/spicetify/Themes/ApplyTheme/user.css";

fn srgb_channel_to_linear(channel: u8) -> f64 {
    let value = channel as f64 / 255.0;
    if value <= 0.04045 {
        value / 12.92
    } else {
        ((value + 0.055) / 1.055).powf(2.4)
    }
}

fn relative_luminance(hex_color: &str) -> f64 {
    let red = srgb_channel_to_linear(u8::from_str_radix(&hex_color[1..3], 16).unwrap());
    let green = srgb_channel_to_linear(u8::from_str_radix(&hex_color[3..5], 16).unwrap());
    let blue = srgb_channel_to_linear(u8::from_str_radix(&hex_color[5..7], 16).unwrap());
    0.2126 * red + 0.7152 * green + 0.0722 * blue
}

fn is_light_scheme(colors: &ColorScheme) -> bool {
    relative_luminance(&colors.bg) > relative_luminance(&colors.fg)
}

fn python_round(value: f64) -> i64 {
    let floor = value.floor();
    let diff = value - floor;
    if diff < 0.5 {
        floor as i64
    } else if diff > 0.5 {
        floor as i64 + 1
    } else {
        let floor_int = floor as i64;
        if floor_int % 2 == 0 {
            floor_int
        } else {
            floor_int + 1
        }
    }
}

fn blend(first: &str, second: &str, factor: f64) -> String {
    let factor = factor.clamp(0.0, 1.0);
    let mut channels = Vec::with_capacity(3);
    for offset in [1, 3, 5] {
        let start = i64::from(u8::from_str_radix(&first[offset..offset + 2], 16).unwrap());
        let end = i64::from(u8::from_str_radix(&second[offset..offset + 2], 16).unwrap());
        let blended = python_round(start as f64 + (end - start) as f64 * factor);
        channels.push(blended as u8);
    }
    format!("#{:02x}{:02x}{:02x}", channels[0], channels[1], channels[2])
}

fn spice_hex(hex_color: &str) -> &str {
    &hex_color[1..]
}

fn shadow(colors: &ColorScheme) -> String {
    if is_light_scheme(colors) {
        colors.bg3.clone()
    } else {
        colors.bg_dim.clone()
    }
}

fn button_active(colors: &ColorScheme) -> String {
    blend(&colors.accent, &colors.fg, 0.18)
}

fn button_disabled(colors: &ColorScheme) -> String {
    if is_light_scheme(colors) {
        colors.fg4.clone()
    } else {
        colors.bg3.clone()
    }
}

pub fn generate(colors: &ColorScheme, _state: &ThemeState) -> crate::Result<GeneratedContent> {
    let mapping = [
        ("text", colors.fg.clone()),
        ("subtext", colors.fg3.clone()),
        ("main", colors.bg.clone()),
        ("sidebar", colors.bg_dim.clone()),
        ("player", colors.bg.clone()),
        ("card", colors.bg1.clone()),
        ("shadow", shadow(colors)),
        ("selected-row", colors.fg2.clone()),
        ("button", colors.accent.clone()),
        ("button-active", button_active(colors)),
        ("button-disabled", button_disabled(colors)),
        ("tab-active", colors.bg2.clone()),
        ("notification", colors.blue.clone()),
        ("notification-error", colors.red.clone()),
        ("misc", colors.fg4.clone()),
    ];

    let mut lines = vec!["[Base]".to_owned()];
    lines.extend(
        mapping
            .into_iter()
            .map(|(key, value)| format!("{key} = {}", spice_hex(&value))),
    );

    Ok(GeneratedContent::text(format!("{}\n", lines.join("\n"))))
}

pub fn persist(_colors: &ColorScheme, _state: &ThemeState) -> crate::Result<()> {
    let user_css_path = expand_user_path(USER_CSS_PATH)?;
    if user_css_path.exists() {
        return Ok(());
    }

    let theme_dir = expand_user_path(THEME_DIR)?;
    fs::create_dir_all(theme_dir)?;
    fs::write(
        user_css_path,
        "/* Optional Spicetify CSS overrides managed outside apply-theme. */\n",
    )?;
    Ok(())
}

pub fn on_apply(_colors: &ColorScheme, _state: &ThemeState) -> crate::Result<()> {
    if find_command("spicetify").is_none() {
        return Ok(());
    }

    let command = vec!["spicetify".to_owned(), "update".to_owned()];
    run_owned_command(&command)
}
