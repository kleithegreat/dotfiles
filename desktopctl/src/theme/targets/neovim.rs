use super::{Assembly, GeneratedContent, TargetMetadata};
use crate::theme::schema::{ColorScheme, ColorSchemeAppearance, ThemeState};
use std::fmt::Write;

pub const METADATA: TargetMetadata =
    TargetMetadata::new("neovim", Assembly::Standalone, &["color_scheme"])
        .output("~/.config/nvim/lua/theme-colors.lua")
        .comment("--");

pub fn generate(colors: &ColorScheme, _state: &ThemeState) -> crate::Result<GeneratedContent> {
    let background = match colors.appearance {
        ColorSchemeAppearance::Dark => "dark",
        ColorSchemeAppearance::Light => "light",
    };

    let named = [
        ("bg", &colors.bg),
        ("bg_dim", &colors.bg_dim),
        ("bg1", &colors.bg1),
        ("bg2", &colors.bg2),
        ("bg3", &colors.bg3),
        ("fg", &colors.fg),
        ("fg2", &colors.fg2),
        ("fg3", &colors.fg3),
        ("fg4", &colors.fg4),
        ("fg_faint", &colors.fg_faint),
        ("red", &colors.red),
        ("green", &colors.green),
        ("yellow", &colors.yellow),
        ("blue", &colors.blue),
        ("purple", &colors.purple),
        ("cyan", &colors.cyan),
        ("orange", &colors.orange),
        ("accent", &colors.accent),
        ("red_bright", &colors.red_bright),
        ("green_bright", &colors.green_bright),
        ("yellow_bright", &colors.yellow_bright),
        ("blue_bright", &colors.blue_bright),
        ("purple_bright", &colors.purple_bright),
        ("cyan_bright", &colors.cyan_bright),
        ("orange_bright", &colors.orange_bright),
    ];

    let mut lua = String::new();
    writeln!(lua, "return {{")?;
    writeln!(lua, "  background = \"{background}\",")?;
    writeln!(lua, "  colors = {{")?;
    for (name, value) in named {
        writeln!(lua, "    {name} = \"{value}\",")?;
    }
    writeln!(lua, "  }},")?;
    writeln!(lua, "  terminal = {{")?;
    for color in &colors.palette {
        writeln!(lua, "    \"{color}\",")?;
    }
    writeln!(lua, "  }},")?;
    writeln!(lua, "}}")?;

    Ok(GeneratedContent::text(lua))
}
