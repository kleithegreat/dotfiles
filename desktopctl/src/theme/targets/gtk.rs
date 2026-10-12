use super::Target;
use crate::theme::{
    atomic_write,
    command::{GNOME_INTERFACE_DCONF_DIR, dconf_write},
    expand_user_path,
    schema::{ColorScheme, ThemeState},
};

const GTK3_SETTINGS: &str = "~/.config/gtk-3.0/settings.ini";
const GTK4_SETTINGS: &str = "~/.config/gtk-4.0/settings.ini";

pub const TARGET: Target = Target::hooks(
    "gtk",
    &[
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
        "adw-gtk3-dark"
    } else {
        "adw-gtk3"
    }
}

fn color_preference(state: &ThemeState) -> &'static str {
    if state.dark_hint {
        "prefer-dark"
    } else {
        "prefer-light"
    }
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

pub fn persist(_colors: &ColorScheme, state: &ThemeState) -> crate::Result<()> {
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
