use super::Target;
use crate::{
    cmd::{GNOME_INTERFACE_DCONF_DIR, dconf_write_str},
    fs_util::{atomic_write, expand_user_path},
    theme::{
        color,
        schema::{ColorScheme, ThemeState},
    },
};
use std::fmt::Write as _;

const GTK3_SETTINGS: &str = "~/.config/gtk-3.0/settings.ini";
const GTK4_SETTINGS: &str = "~/.config/gtk-4.0/settings.ini";
const GTK4_CSS: &str = "~/.config/gtk-4.0/gtk.css";
/// The theme `home/gtk.nix` installs; both its variants load `scheme.css`.
const THEME: &str = "desktopctl";

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

/// The portal's `color-scheme`: the browser's `dark_hint`, not the scheme's polarity.
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
        ("headerbar_border_color", fg()),
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

/// libadwaita clamps a fill colour to this lightness for standalone text.
fn standalone_lightness(colors: &ColorScheme) -> &'static str {
    if colors.is_dark() {
        "max(l, 0.85)"
    } else {
        "min(l, 0.5)"
    }
}

/// Everything libadwaita's `@media (prefers-color-scheme: dark)` blocks
/// change, set from the scheme's own appearance. The portal preference those
/// blocks follow is the browser's, so any value left out here leaks it.
fn appearance_colors(colors: &ColorScheme) -> Vec<(&'static str, String)> {
    let dark = colors.is_dark();
    let pick = |light: &str, dark_value: &str| if dark { dark_value } else { light }.to_owned();
    let lightness = standalone_lightness(colors);
    let standalone = |role: &str| format!("oklab(from @{role}_bg_color {lightness} a b)");
    vec![
        ("accent_color", standalone("accent")),
        ("destructive_color", standalone("destructive")),
        ("success_color", standalone("success")),
        ("warning_color", standalone("warning")),
        ("error_color", standalone("error")),
        (
            "headerbar_shade_color",
            pick("RGB(0 0 6 / 12%)", "RGB(0 0 6 / 36%)"),
        ),
        (
            "headerbar_darker_shade_color",
            pick("RGB(0 0 6 / 12%)", "RGB(0 0 12 / 90%)"),
        ),
        (
            "sidebar_shade_color",
            pick("RGB(0 0 6 / 7%)", "RGB(0 0 6 / 25%)"),
        ),
        (
            "sidebar_border_color",
            pick("RGB(0 0 6 / 7%)", "RGB(0 0 6 / 36%)"),
        ),
        (
            "secondary_sidebar_shade_color",
            pick("RGB(0 0 6 / 7%)", "RGB(0 0 6 / 25%)"),
        ),
        (
            "secondary_sidebar_border_color",
            pick("RGB(0 0 6 / 7%)", "RGB(0 0 6 / 36%)"),
        ),
        (
            "card_shade_color",
            pick("RGB(0 0 6 / 7%)", "RGB(0 0 6 / 36%)"),
        ),
        (
            "popover_shade_color",
            pick("RGB(0 0 6 / 7%)", "RGB(0 0 6 / 25%)"),
        ),
        ("shade_color", pick("RGB(0 0 6 / 7%)", "RGB(0 0 6 / 25%)")),
        (
            "scrollbar_outline_color",
            pick("white", "RGB(0 0 12 / 95%)"),
        ),
    ]
}

fn define_colors(defines: &[(&str, String)]) -> String {
    let mut css = String::new();
    for (name, value) in defines {
        writeln!(css, "@define-color {name} {value};").expect("writing to a String");
    }
    css
}

/// Selects the theme's adw-gtk3 base by the scheme's appearance, never by
/// GTK's dark variant: libhandy sets that from the portal.
fn base_import(colors: &ColorScheme) -> String {
    let base = if colors.is_dark() { "dark" } else { "light" };
    format!("@import url(\"{base}.css\");\n")
}

/// The user provider outranks libadwaita, so these hold at either portal preference.
fn gtk4_css(colors: &ColorScheme) -> String {
    let dark = colors.is_dark();
    let mut defines = named_colors(colors);
    defines.extend(appearance_colors(colors));
    format!(
        concat!(
            "{}\n",
            ":root {{\n",
            "  --standalone-color-oklab: {} a b;\n",
            "  --active-toggle-bg-color: {};\n",
            "  --active-toggle-fg-color: {};\n",
            "  --overview-bg-color: {};\n",
            "  --overview-fg-color: {};\n",
            "}}\n",
        ),
        define_colors(&defines),
        standalone_lightness(colors),
        if dark {
            "rgb(255 255 255 / 20%)"
        } else {
            &colors.bg
        },
        colors.fg,
        colors.bg_dim,
        colors.fg,
    )
}

fn settings_ini(colors: &ColorScheme, state: &ThemeState) -> crate::Result<String> {
    Ok(format!(
        concat!(
            "[Settings]\n",
            "gtk-theme-name={}\n",
            "gtk-icon-theme-name={}\n",
            "gtk-font-name={} {}\n",
            "gtk-application-prefer-dark-theme={}\n",
        ),
        THEME,
        state.icon_theme,
        state.system_font,
        state.font_size_for(TARGET.name)?,
        colors.is_dark(),
    ))
}

pub fn persist(colors: &ColorScheme, state: &ThemeState) -> crate::Result<()> {
    atomic_write(&expand_user_path(GTK4_CSS)?, gtk4_css(colors).as_bytes())?;
    let scheme_css = |toolkit: &str| {
        expand_user_path(&format!(
            "~/.local/share/themes/{THEME}/{toolkit}/scheme.css"
        ))
    };
    let base = base_import(colors);
    atomic_write(
        &scheme_css("gtk-3.0")?,
        format!("{base}{}", define_colors(&named_colors(colors))).as_bytes(),
    )?;
    atomic_write(&scheme_css("gtk-4.0")?, base.as_bytes())?;

    let contents = settings_ini(colors, state)?;
    for path in [GTK3_SETTINGS, GTK4_SETTINGS] {
        atomic_write(&expand_user_path(path)?, contents.as_bytes())?;
    }
    Ok(())
}

pub fn on_apply(_colors: &ColorScheme, state: &ThemeState) -> crate::Result<()> {
    let font = |family: &str, size: i64| format!("{family} {size}");
    for (key, value) in [
        ("gtk-theme", THEME.to_owned()),
        ("color-scheme", color_preference(state).to_owned()),
        (
            "font-name",
            font(&state.system_font, state.font_size_for(TARGET.name)?),
        ),
        (
            "monospace-font-name",
            font(&state.mono_font, state.mono_font_size_for(TARGET.name)?),
        ),
        ("icon-theme", state.icon_theme.clone()),
    ] {
        dconf_write_str(&format!("{GNOME_INTERFACE_DCONF_DIR}/{key}"), &value)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::named_colors;
    use crate::theme::{
        color::contrast_ratio,
        targets::testsupport::{load_repo_colors, repo_schemes},
    };

    #[test]
    fn text_on_status_fills_is_readable() {
        for scheme in repo_schemes() {
            let colors = named_colors(&load_repo_colors(&scheme));
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
