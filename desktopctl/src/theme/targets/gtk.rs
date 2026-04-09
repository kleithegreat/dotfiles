use super::{Assembly, GeneratedContent, TargetMetadata};
use crate::theme::schema::{ColorScheme, ThemeState};
use std::process::Command;

pub const METADATA: TargetMetadata = TargetMetadata {
    name: "gtk",
    assembly: Assembly::Command,
    output_path: None,
    base_path: None,
    extra_outputs: &[],
    reload_cmd: None,
    comment: None,
    sync_safe: false,
};

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

pub fn on_apply(_colors: &ColorScheme, state: &ThemeState) -> crate::Result<()> {
    let gtk_theme = if state.dark_hint {
        "adw-gtk3-dark"
    } else {
        "adw-gtk3"
    };
    let color_pref = if state.dark_hint {
        "prefer-dark"
    } else {
        "prefer-light"
    };

    dconf_set("gtk-theme", &format!("'{gtk_theme}'"))?;
    dconf_set("color-scheme", &format!("'{color_pref}'"))?;
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
