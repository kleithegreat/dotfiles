use super::{Assembly, GeneratedContent, TargetMetadata};
use crate::theme::{
    atomic_write, expand_user_path,
    schema::{ColorScheme, ThemeState},
};
use std::process::Command;

const GTK3_SETTINGS: &str = "~/.config/gtk-3.0/settings.ini";
const GTK4_SETTINGS: &str = "~/.config/gtk-4.0/settings.ini";

pub const METADATA: TargetMetadata = TargetMetadata::new(
    "gtk",
    Assembly::Command,
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
.managed_paths(&[GTK3_SETTINGS, GTK4_SETTINGS]);

fn dconf_set(key: &str, value: &str) -> crate::Result<()> {
    let output = Command::new("dconf")
        .args([
            "write",
            &format!("/org/gnome/desktop/interface/{key}"),
            value,
        ])
        .output();
    let output = output?;
    if output.status.success() {
        return Ok(());
    }
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_owned();
    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_owned();
    let message = if !stderr.is_empty() {
        stderr
    } else if !stdout.is_empty() {
        stdout
    } else {
        format!("command exited with status {}", output.status)
    };
    Err(std::io::Error::other(message).into())
}

pub fn generate(_colors: &ColorScheme, _state: &ThemeState) -> crate::Result<GeneratedContent> {
    Ok(GeneratedContent::commands(Vec::new()))
}

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
        state.font_size_for(METADATA.name)?,
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
    dconf_set("gtk-theme", &format!("'{}'", gtk_theme(state)))?;
    dconf_set("color-scheme", &format!("'{}'", color_preference(state)))?;
    dconf_set(
        "font-name",
        &format!(
            "'{} {}'",
            state.system_font,
            state.font_size_for(METADATA.name)?,
        ),
    )?;
    dconf_set(
        "monospace-font-name",
        &format!(
            "'{} {}'",
            state.mono_font,
            state.mono_font_size_for(METADATA.name)?,
        ),
    )?;
    dconf_set("icon-theme", &format!("'{}'", state.icon_theme))?;
    Ok(())
}
