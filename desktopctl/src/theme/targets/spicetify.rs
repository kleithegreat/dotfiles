use super::Target;
use crate::theme::{
    atomic_write,
    color::blend_rounded,
    command::{find_command, run},
    expand_user_path,
    schema::{ColorScheme, ThemeState},
};
use std::fs;

pub const TARGET: Target = Target::standalone(
    "spicetify",
    &["color_scheme"],
    "~/.config/spicetify/Themes/ApplyTheme/color.ini",
    generate,
)
.comment(";")
.persist(persist)
.on_apply(on_apply);

const THEME_DIR: &str = "~/.config/spicetify/Themes/ApplyTheme";
const USER_CSS_PATH: &str = "~/.config/spicetify/Themes/ApplyTheme/user.css";

fn spice_hex(hex_color: &str) -> &str {
    &hex_color[1..]
}

fn shadow(colors: &ColorScheme) -> String {
    if colors.is_light() {
        colors.bg3.clone()
    } else {
        colors.bg_dim.clone()
    }
}

fn button_active(colors: &ColorScheme) -> String {
    blend_rounded(&colors.accent, &colors.fg, 0.18, f64::round_ties_even)
}

fn button_disabled(colors: &ColorScheme) -> String {
    if colors.is_light() {
        colors.fg4.clone()
    } else {
        colors.bg3.clone()
    }
}

pub fn generate(colors: &ColorScheme, _state: &ThemeState) -> crate::Result<String> {
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

    Ok(format!("{}\n", lines.join("\n")))
}

pub fn persist(_colors: &ColorScheme, _state: &ThemeState) -> crate::Result<()> {
    let user_css_path = expand_user_path(USER_CSS_PATH)?;
    if user_css_path.exists() {
        return Ok(());
    }

    let theme_dir = expand_user_path(THEME_DIR)?;
    fs::create_dir_all(theme_dir)?;
    atomic_write(
        &user_css_path,
        b"/* Optional Spicetify CSS overrides managed outside desktopctl. */\n",
    )
}

pub fn on_apply(_colors: &ColorScheme, _state: &ThemeState) -> crate::Result<()> {
    if find_command("spicetify").is_none() {
        return Ok(());
    }

    run(&["spicetify", "update"])
}
