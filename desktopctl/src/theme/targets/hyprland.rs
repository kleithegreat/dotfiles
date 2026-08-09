use super::{Assembly, GeneratedContent, TargetMetadata};
use crate::theme::{
    atomic_write, expand_user_path,
    schema::{ColorScheme, ThemeState},
};
use std::fs;

const RELOAD_CMD: &[&str] = &["hyprctl", "reload"];

pub const METADATA: TargetMetadata = TargetMetadata::new(
    "hyprland",
    Assembly::Standalone,
    &["color_scheme", "mono_font", "system_font"],
)
.output("~/.config/hypr/colors.lua")
.managed_paths(&["~/.config/hypr/colors.conf"])
.reload_cmd(RELOAD_CMD)
.comment("--");

/// hyprlock is a separate application that still uses hyprlang, so it needs the
/// same palette as `$theme_*` variables alongside the Lua table Hyprland reads.
const HYPRLOCK_COLORS_CONF: &str = "~/.config/hypr/colors.conf";

fn rgb(hex_color: &str) -> String {
    format!("rgb({})", &hex_color[1..])
}

fn rgba(hex_color: &str, alpha: &str) -> String {
    format!("rgba({}{alpha})", &hex_color[1..])
}

/// Quote a value as a Lua string literal. Colors are generated from a fixed
/// palette, but font names come from user config and can contain anything.
fn lua_str(value: &str) -> String {
    let escaped = value
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
        .replace('\r', "\\r");
    format!("\"{escaped}\"")
}

pub fn generate(colors: &ColorScheme, state: &ThemeState) -> crate::Result<GeneratedContent> {
    Ok(GeneratedContent::text(format!(
        concat!(
            "return {{\n",
            "    bg             = {},\n",
            "    bg_rgba        = {},\n",
            "    bg_dim         = {},\n",
            "    bg_dim_rgba    = {},\n",
            "    bg1            = {},\n",
            "    bg1_rgba       = {},\n",
            "    bg2            = {},\n",
            "    bg2_rgba       = {},\n",
            "    bg3            = {},\n",
            "    bg3_rgba       = {},\n",
            "    fg             = {},\n",
            "    fg_rgba        = {},\n",
            "    accent         = {},\n",
            "    accent_rgba    = {},\n",
            "    red            = {},\n",
            "    red_rgba       = {},\n",
            "    green          = {},\n",
            "    green_rgba     = {},\n",
            "    yellow         = {},\n",
            "    yellow_rgba    = {},\n",
            "    blue           = {},\n",
            "    blue_rgba      = {},\n",
            "    purple         = {},\n",
            "    purple_rgba    = {},\n",
            "    cyan           = {},\n",
            "    cyan_rgba      = {},\n",
            "    orange         = {},\n",
            "    orange_rgba    = {},\n",
            "    font           = {},\n",
            "    sys_font       = {},\n",
            "}}\n",
        ),
        lua_str(&rgb(&colors.bg)),
        lua_str(&rgba(&colors.bg, "ff")),
        lua_str(&rgb(&colors.bg_dim)),
        lua_str(&rgba(&colors.bg_dim, "ff")),
        lua_str(&rgb(&colors.bg1)),
        lua_str(&rgba(&colors.bg1, "ff")),
        lua_str(&rgb(&colors.bg2)),
        lua_str(&rgba(&colors.bg2, "ff")),
        lua_str(&rgb(&colors.bg3)),
        lua_str(&rgba(&colors.bg3, "ff")),
        lua_str(&rgb(&colors.fg)),
        lua_str(&rgba(&colors.fg, "ff")),
        lua_str(&rgb(&colors.accent)),
        lua_str(&rgba(&colors.accent, "ff")),
        lua_str(&rgb(&colors.red)),
        lua_str(&rgba(&colors.red, "ff")),
        lua_str(&rgb(&colors.green)),
        lua_str(&rgba(&colors.green, "ff")),
        lua_str(&rgb(&colors.yellow)),
        lua_str(&rgba(&colors.yellow, "ff")),
        lua_str(&rgb(&colors.blue)),
        lua_str(&rgba(&colors.blue, "ff")),
        lua_str(&rgb(&colors.purple)),
        lua_str(&rgba(&colors.purple, "ff")),
        lua_str(&rgb(&colors.cyan)),
        lua_str(&rgba(&colors.cyan, "ff")),
        lua_str(&rgb(&colors.orange)),
        lua_str(&rgba(&colors.orange, "ff")),
        lua_str(&state.mono_font),
        lua_str(&state.system_font),
    )))
}

/// Render the same palette as hyprlang `$theme_*` variables for hyprlock,
/// which is a separate application and still parses hyprlang.
fn hyprlock_colors_text(colors: &ColorScheme, state: &ThemeState) -> String {
    let pairs: [(&str, String); 30] = [
        ("bg", rgb(&colors.bg)),
        ("bg_rgba", rgba(&colors.bg, "ff")),
        ("bg_dim", rgb(&colors.bg_dim)),
        ("bg_dim_rgba", rgba(&colors.bg_dim, "ff")),
        ("bg1", rgb(&colors.bg1)),
        ("bg1_rgba", rgba(&colors.bg1, "ff")),
        ("bg2", rgb(&colors.bg2)),
        ("bg2_rgba", rgba(&colors.bg2, "ff")),
        ("bg3", rgb(&colors.bg3)),
        ("bg3_rgba", rgba(&colors.bg3, "ff")),
        ("fg", rgb(&colors.fg)),
        ("fg_rgba", rgba(&colors.fg, "ff")),
        ("accent", rgb(&colors.accent)),
        ("accent_rgba", rgba(&colors.accent, "ff")),
        ("red", rgb(&colors.red)),
        ("red_rgba", rgba(&colors.red, "ff")),
        ("green", rgb(&colors.green)),
        ("green_rgba", rgba(&colors.green, "ff")),
        ("yellow", rgb(&colors.yellow)),
        ("yellow_rgba", rgba(&colors.yellow, "ff")),
        ("blue", rgb(&colors.blue)),
        ("blue_rgba", rgba(&colors.blue, "ff")),
        ("purple", rgb(&colors.purple)),
        ("purple_rgba", rgba(&colors.purple, "ff")),
        ("cyan", rgb(&colors.cyan)),
        ("cyan_rgba", rgba(&colors.cyan, "ff")),
        ("orange", rgb(&colors.orange)),
        ("orange_rgba", rgba(&colors.orange, "ff")),
        ("font", state.mono_font.clone()),
        ("sys_font", state.system_font.clone()),
    ];

    let mut out = String::from("# Generated by desktopctl theme — do not edit\n");
    for (name, value) in pairs {
        out.push_str(&format!("$theme_{name} = {value}\n"));
    }
    out
}

pub fn persist(colors: &ColorScheme, state: &ThemeState) -> crate::Result<()> {
    let path = expand_user_path(HYPRLOCK_COLORS_CONF)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    atomic_write(&path, hyprlock_colors_text(colors, state).as_bytes())
}
