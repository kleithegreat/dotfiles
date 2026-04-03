use super::{Assembly, GeneratedContent, TargetMetadata};
use crate::theme::schema::{ColorScheme, ThemeState};

pub const METADATA: TargetMetadata = TargetMetadata {
    name: "starship",
    assembly: Assembly::Concat,
    output_path: Some("~/.config/starship.toml"),
    base_path: Some("~/repos/dotfiles/config/starship/base.toml"),
    extra_outputs: &[],
    reload_cmd: None,
    comment: Some("#"),
    sync_safe: true,
};

const WCAG_AA_NORMAL_TEXT: f64 = 4.5;

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

fn contrast_ratio(first: &str, second: &str) -> f64 {
    let first_luminance = relative_luminance(first);
    let second_luminance = relative_luminance(second);
    let lighter = first_luminance.max(second_luminance);
    let darker = first_luminance.min(second_luminance);
    (lighter + 0.05) / (darker + 0.05)
}

fn accent_foreground(accent: &str, colors: &ColorScheme) -> String {
    let candidates = [
        colors.fg.as_str(),
        colors.bg.as_str(),
        colors.fg2.as_str(),
        colors.fg3.as_str(),
        colors.fg4.as_str(),
        colors.bg_dim.as_str(),
        colors.bg1.as_str(),
        colors.bg2.as_str(),
        colors.bg3.as_str(),
    ];
    for candidate in candidates {
        if contrast_ratio(accent, candidate) >= WCAG_AA_NORMAL_TEXT {
            return candidate.to_owned();
        }
    }

    let black = "#000000";
    let white = "#ffffff";
    if contrast_ratio(accent, black) >= contrast_ratio(accent, white) {
        black.to_owned()
    } else {
        white.to_owned()
    }
}

pub fn generate(colors: &ColorScheme, _state: &ThemeState) -> crate::Result<GeneratedContent> {
    Ok(GeneratedContent::text(format!(
        concat!(
            "\n[palettes.current]\n",
            "color_fg0 = '{}'\n",
            "color_bg1 = '{}'\n",
            "color_bg3 = '{}'\n",
            "color_blue = '{}'\n",
            "color_blue_fg = '{}'\n",
            "color_aqua = '{}'\n",
            "color_aqua_fg = '{}'\n",
            "color_green = '{}'\n",
            "color_orange = '{}'\n",
            "color_orange_fg = '{}'\n",
            "color_purple = '{}'\n",
            "color_red = '{}'\n",
            "color_yellow = '{}'\n",
            "color_yellow_fg = '{}'\n",
        ),
        colors.fg,
        colors.bg1,
        colors.bg3,
        colors.blue,
        accent_foreground(&colors.blue, colors),
        colors.cyan,
        accent_foreground(&colors.cyan, colors),
        colors.green,
        colors.orange,
        accent_foreground(&colors.orange, colors),
        colors.purple,
        colors.red,
        colors.yellow,
        accent_foreground(&colors.yellow, colors),
    )))
}
