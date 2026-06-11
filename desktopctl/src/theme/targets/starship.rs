use super::{Assembly, GeneratedContent, TargetMetadata, color_utils::contrast_ratio};
use crate::theme::schema::{ColorScheme, ThemeState};

pub const METADATA: TargetMetadata =
    TargetMetadata::new("starship", Assembly::Concat, &["color_scheme"])
        .output("~/.config/starship.toml")
        .base("config/starship/base.toml")
        .comment("#");

const WCAG_AA_NORMAL_TEXT: f64 = 4.5;

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
            "color_blue_bright = '{}'\n",
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
        colors.blue_bright,
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
