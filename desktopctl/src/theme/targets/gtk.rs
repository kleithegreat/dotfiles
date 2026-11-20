use super::{Target, scheme_pair};
use crate::theme::{
    atomic_write, color,
    command::{GNOME_INTERFACE_DCONF_DIR, dconf_write},
    expand_user_path,
    schema::{ColorScheme, ColorSchemeAppearance, ThemeState},
};
use std::fmt::Write as _;

const GTK3_SETTINGS: &str = "~/.config/gtk-3.0/settings.ini";
const GTK4_SETTINGS: &str = "~/.config/gtk-4.0/settings.ini";
const GTK4_CSS: &str = "~/.config/gtk-4.0/gtk.css";
/// The GTK3 themes `home/gtk.nix` installs; each imports its `colors.css`.
const LIGHT_THEME: &str = "desktopctl";
const DARK_THEME: &str = "desktopctl-dark";

pub const TARGET: Target = Target::hooks(
    "gtk",
    &[
        "color_scheme",
        "dark_hint",
        "system_font",
        "mono_font",
        "icon_theme",
        "font_size",
        "gtk_font_size_offset",
        "mono_font_size",
        "gtk_mono_font_size_offset",
    ],
)
.persist(persist)
.on_apply(on_apply);

fn gtk_theme(state: &ThemeState) -> &'static str {
    if state.dark_hint {
        DARK_THEME
    } else {
        LIGHT_THEME
    }
}

fn color_preference(state: &ThemeState) -> &'static str {
    if state.dark_hint {
        "prefer-dark"
    } else {
        "prefer-light"
    }
}

/// libadwaita's named colors, which adw-gtk3 shares.
fn named_colors(colors: &ColorScheme) -> Vec<(&'static str, String)> {
    let on = |plate: &str| color::readable_on_ends(plate, &colors.bg, &colors.fg);
    let fg = || colors.fg.clone();
    let chrome = || colors.bg1.clone();
    vec![
        ("accent_bg_color", colors.accent.clone()),
        ("accent_fg_color", on(&colors.accent)),
        ("destructive_bg_color", colors.red.clone()),
        ("destructive_fg_color", on(&colors.red)),
        ("success_bg_color", colors.green.clone()),
        ("success_fg_color", on(&colors.green)),
        ("warning_bg_color", colors.yellow.clone()),
        ("warning_fg_color", on(&colors.yellow)),
        ("error_bg_color", colors.red.clone()),
        ("error_fg_color", on(&colors.red)),
        ("window_bg_color", colors.bg.clone()),
        ("window_fg_color", fg()),
        ("view_bg_color", colors.bg.clone()),
        ("view_fg_color", fg()),
        ("headerbar_bg_color", chrome()),
        ("headerbar_backdrop_color", chrome()),
        ("headerbar_fg_color", fg()),
        ("sidebar_bg_color", chrome()),
        ("sidebar_backdrop_color", chrome()),
        ("sidebar_fg_color", fg()),
        ("secondary_sidebar_bg_color", chrome()),
        ("secondary_sidebar_backdrop_color", chrome()),
        ("secondary_sidebar_fg_color", fg()),
        ("card_bg_color", chrome()),
        ("card_fg_color", fg()),
        ("dialog_bg_color", chrome()),
        ("dialog_fg_color", fg()),
        ("popover_bg_color", chrome()),
        ("popover_fg_color", fg()),
        ("thumbnail_bg_color", chrome()),
        ("thumbnail_fg_color", fg()),
    ]
}

fn define_colors(colors: &ColorScheme, indent: &str) -> String {
    let mut css = String::new();
    for (name, value) in named_colors(colors) {
        writeln!(css, "{indent}@define-color {name} {value};").expect("writing to a String");
    }
    css
}

/// Both appearances in one file, so libadwaita follows a polarity flip live.
fn gtk4_css(light: &ColorScheme, dark: &ColorScheme) -> String {
    format!(
        "{}\n@media (prefers-color-scheme: dark) {{\n{}}}\n",
        define_colors(light, ""),
        define_colors(dark, "  "),
    )
}

fn settings_ini(state: &ThemeState) -> crate::Result<String> {
    Ok(format!(
        concat!(
            "[Settings]\n",
            "gtk-theme-name={}\n",
            "gtk-icon-theme-name={}\n",
            "gtk-font-name={} {}\n",
            "gtk-application-prefer-dark-theme={}\n",
        ),
        gtk_theme(state),
        state.icon_theme,
        state.system_font,
        state.font_size_for(TARGET.name)?,
        if state.dark_hint { "true" } else { "false" },
    ))
}

pub fn persist(colors: &ColorScheme, state: &ThemeState) -> crate::Result<()> {
    let light = scheme_pair::colors_for_appearance(colors, ColorSchemeAppearance::Light)?;
    let dark = scheme_pair::colors_for_appearance(colors, ColorSchemeAppearance::Dark)?;

    atomic_write(
        &expand_user_path(GTK4_CSS)?,
        gtk4_css(&light, &dark).as_bytes(),
    )?;
    for (theme, colors) in [(LIGHT_THEME, &light), (DARK_THEME, &dark)] {
        atomic_write(
            &expand_user_path(&format!("~/.local/share/themes/{theme}/gtk-3.0/colors.css"))?,
            define_colors(colors, "").as_bytes(),
        )?;
    }

    let contents = settings_ini(state)?;
    for path in [GTK3_SETTINGS, GTK4_SETTINGS] {
        atomic_write(&expand_user_path(path)?, contents.as_bytes())?;
    }
    Ok(())
}

pub fn on_apply(_colors: &ColorScheme, state: &ThemeState) -> crate::Result<()> {
    let font = |family: &str, size: i64| format!("'{family} {size}'");
    for (key, value) in [
        ("gtk-theme", format!("'{}'", gtk_theme(state))),
        ("color-scheme", format!("'{}'", color_preference(state))),
        (
            "font-name",
            font(&state.system_font, state.font_size_for(TARGET.name)?),
        ),
        (
            "monospace-font-name",
            font(&state.mono_font, state.mono_font_size_for(TARGET.name)?),
        ),
        ("icon-theme", format!("'{}'", state.icon_theme)),
    ] {
        dconf_write(&format!("{GNOME_INTERFACE_DCONF_DIR}/{key}"), &value)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{gtk4_css, named_colors};
    use crate::theme::{
        color::contrast_ratio,
        targets::testsupport::{REPO_SCHEMES, load_repo_colors},
    };

    #[test]
    fn gtk4_css_puts_dark_colors_under_the_media_query() {
        let light = load_repo_colors("gruvbox-light");
        let dark = load_repo_colors("gruvbox-dark");
        let css = gtk4_css(&light, &dark);
        let (top, media) = css
            .split_once("@media (prefers-color-scheme: dark)")
            .expect("dark block present");
        assert!(top.contains(&format!("@define-color view_bg_color {};", light.bg)));
        assert!(media.contains(&format!("@define-color view_bg_color {};", dark.bg)));
    }

    #[test]
    fn text_on_status_fills_is_readable() {
        for scheme in REPO_SCHEMES {
            let colors = named_colors(&load_repo_colors(scheme));
            let get = |name: &str| {
                colors
                    .iter()
                    .find(|(key, _)| *key == name)
                    .map(|(_, value)| value.as_str())
                    .expect("named color present")
            };
            for role in ["accent", "destructive", "success", "warning", "error"] {
                let ratio = contrast_ratio(
                    get(&format!("{role}_bg_color")),
                    get(&format!("{role}_fg_color")),
                );
                assert!(ratio >= 3.0, "{scheme} {role}: {ratio:.2}");
            }
        }
    }
}
