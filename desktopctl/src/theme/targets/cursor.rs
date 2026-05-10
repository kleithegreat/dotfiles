use super::{Assembly, GeneratedContent, TargetMetadata};
use crate::theme::{
    atomic_write, expand_user_path,
    schema::{ColorScheme, ThemeState},
};
use std::{
    collections::BTreeMap,
    fs,
    path::Path,
    process::{self, Command},
};

#[cfg(unix)]
use std::os::unix::fs::symlink;

pub const METADATA: TargetMetadata = TargetMetadata::new(
    "cursor",
    Assembly::Standalone,
    &["cursor_theme", "cursor_size"],
)
.output("~/.local/share/icons/default/index.theme.generated")
.managed_paths(&[
    "~/.config/hypr/cursor.conf",
    "~/.local/share/icons/default/index.theme",
    "~/.icons/default/index.theme",
])
.comment("#");

const HYPR_CURSOR_CONF: &str = "~/.config/hypr/cursor.conf";
const XCURSOR_INDEX: &str = "~/.local/share/icons/default/index.theme";
const LEGACY_XCURSOR_INDEX: &str = "~/.icons/default/index.theme";

fn index_theme_text(cursor_theme: &str) -> String {
    format!("[Icon Theme]\nName=Default\nInherits={cursor_theme}\n")
}

fn dconf_set(key: &str, value: &str) -> crate::Result<()> {
    run(
        &[
            "dconf".to_owned(),
            "write".to_owned(),
            format!("/org/gnome/desktop/interface/{key}"),
            value.to_owned(),
        ],
        None,
    )
}

fn run(command: &[String], env_overrides: Option<&BTreeMap<String, String>>) -> crate::Result<()> {
    let mut process = Command::new(&command[0]);
    process.args(&command[1..]);
    if let Some(env_overrides) = env_overrides {
        process.envs(env_overrides);
    }
    let output = process.output()?;
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

fn hyprctl_cursor_theme(cursor_theme: &str) -> &str {
    match cursor_theme {
        "BreezeX-RosePine-Linux" => "rose-pine-hyprcursor",
        _ => cursor_theme,
    }
}

fn hyprcursor_env_theme(cursor_theme: &str) -> Option<&str> {
    match cursor_theme {
        "BreezeX-RosePine-Linux" => Some("rose-pine-hyprcursor"),
        _ => None,
    }
}

fn hyprctl_env(variable: &str, value: &str) -> crate::Result<()> {
    run(
        &[
            "hyprctl".to_owned(),
            "keyword".to_owned(),
            "env".to_owned(),
            format!("{variable},{value}"),
        ],
        None,
    )
}

fn import_user_env(values: &BTreeMap<String, String>) {
    let keys = values.keys().cloned().collect::<Vec<_>>();
    let args = std::iter::once("systemctl".to_owned())
        .chain(std::iter::once("--user".to_owned()))
        .chain(std::iter::once("import-environment".to_owned()))
        .chain(keys.clone())
        .collect::<Vec<_>>();
    let _ = run(&args, Some(values));

    let dbus_args = std::iter::once("dbus-update-activation-environment".to_owned())
        .chain(std::iter::once("--systemd".to_owned()))
        .chain(values.iter().map(|(key, value)| format!("{key}={value}")))
        .collect::<Vec<_>>();
    let _ = run(&dbus_args, None);
}

fn unset_user_env(keys: &[&str]) {
    if keys.is_empty() {
        return;
    }

    let systemctl_args = std::iter::once("systemctl".to_owned())
        .chain(std::iter::once("--user".to_owned()))
        .chain(std::iter::once("unset-environment".to_owned()))
        .chain(keys.iter().map(|key| (*key).to_owned()))
        .collect::<Vec<_>>();
    let _ = run(&systemctl_args, None);

    let dbus_args = std::iter::once("dbus-update-activation-environment".to_owned())
        .chain(std::iter::once("--systemd".to_owned()))
        .chain(keys.iter().map(|key| format!("{key}=")))
        .collect::<Vec<_>>();
    let _ = run(&dbus_args, None);
}

fn replace_with_symlink(
    link_path: &Path,
    target: &Path,
    fallback_contents: &str,
) -> crate::Result<()> {
    #[cfg(unix)]
    {
        let parent = link_path.parent().unwrap_or_else(|| Path::new("."));
        let file_name = link_path
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("index.theme");

        for attempt in 0..16 {
            let temp_path = parent.join(format!(
                ".{file_name}.desktopctl-{}-{attempt}.tmp",
                process::id()
            ));
            match symlink(target, &temp_path) {
                Ok(()) => {
                    if let Err(error) = fs::rename(&temp_path, link_path) {
                        let _ = fs::remove_file(&temp_path);
                        return Err(error.into());
                    }
                    return Ok(());
                }
                Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(_) => break,
            }
        }
    }

    atomic_write(link_path, fallback_contents.as_bytes())
}

pub fn generate(_colors: &ColorScheme, state: &ThemeState) -> crate::Result<GeneratedContent> {
    Ok(GeneratedContent::text(index_theme_text(
        &state.cursor_theme,
    )))
}

pub fn persist(_colors: &ColorScheme, state: &ThemeState) -> crate::Result<()> {
    let generated_path = expand_user_path(METADATA.output_path.expect("cursor output path"))?;
    let xcursor_index = expand_user_path(XCURSOR_INDEX)?;
    let legacy_index = expand_user_path(LEGACY_XCURSOR_INDEX)?;
    let conf_path = expand_user_path(HYPR_CURSOR_CONF)?;

    if let Some(parent) = conf_path.parent() {
        fs::create_dir_all(parent)?;
    }
    let mut lines = vec![
        "# Generated by apply-theme -- do not edit".to_owned(),
        format!("env = XCURSOR_THEME,{}", state.cursor_theme),
        format!("env = XCURSOR_SIZE,{}", state.cursor_size),
    ];
    if let Some(hyprcursor_theme) = hyprcursor_env_theme(&state.cursor_theme) {
        lines.push(format!("env = HYPRCURSOR_THEME,{hyprcursor_theme}"));
    }
    atomic_write(&conf_path, format!("{}\n", lines.join("\n")).as_bytes())?;

    for index_path in [xcursor_index, legacy_index] {
        if let Some(parent) = index_path.parent() {
            fs::create_dir_all(parent)?;
        }
        replace_with_symlink(
            &index_path,
            &generated_path,
            &index_theme_text(&state.cursor_theme),
        )?;
    }

    Ok(())
}

pub fn on_apply(_colors: &ColorScheme, state: &ThemeState) -> crate::Result<()> {
    dconf_set("cursor-theme", &format!("'{}'", state.cursor_theme))?;
    dconf_set("cursor-size", &state.cursor_size.to_string())?;

    let hyprcursor_theme = hyprcursor_env_theme(&state.cursor_theme);
    let mut session_env = BTreeMap::from([
        ("XCURSOR_THEME".to_owned(), state.cursor_theme.clone()),
        ("XCURSOR_SIZE".to_owned(), state.cursor_size.to_string()),
    ]);

    hyprctl_env("XCURSOR_THEME", &state.cursor_theme)?;
    hyprctl_env("XCURSOR_SIZE", &state.cursor_size.to_string())?;

    if let Some(hyprcursor_theme) = hyprcursor_theme {
        hyprctl_env("HYPRCURSOR_THEME", hyprcursor_theme)?;
        session_env.insert("HYPRCURSOR_THEME".to_owned(), hyprcursor_theme.to_owned());
    } else {
        hyprctl_env("HYPRCURSOR_THEME", "")?;
    }

    run(
        &[
            "hyprctl".to_owned(),
            "setcursor".to_owned(),
            hyprctl_cursor_theme(&state.cursor_theme).to_owned(),
            state.cursor_size.to_string(),
        ],
        None,
    )?;

    import_user_env(&session_env);
    if hyprcursor_theme.is_none() {
        unset_user_env(&["HYPRCURSOR_THEME"]);
    }
    Ok(())
}
