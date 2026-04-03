use crate::paths;
use serde::Deserialize;
use std::{
    env, io,
    path::PathBuf,
    process::{Command, Output},
};

type Result<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct WindowInfo {
    #[serde(default)]
    pub(crate) class: String,
    #[serde(rename = "initialClass", default)]
    pub(crate) initial_class: String,
    #[serde(default)]
    floating: bool,
}

/// Query Hyprland for the currently active window.
pub(crate) fn active_window() -> Result<WindowInfo> {
    let output = hyprctl_output(&["activewindow", "-j"])?;
    Ok(serde_json::from_slice(&output.stdout)?)
}

/// Run `hyprctl dispatch ...`.
pub(crate) fn dispatch(args: &[&str]) -> Result<()> {
    let mut command_args = Vec::with_capacity(args.len() + 1);
    command_args.push("dispatch");
    command_args.extend(args.iter().copied());
    hyprctl_output(&command_args)?;
    Ok(())
}

/// Run `hyprctl --batch ...`.
fn batch(commands: &[&str]) -> Result<()> {
    if commands.is_empty() {
        return Ok(());
    }

    let batch = commands.join(" ; ");
    hyprctl_output(&["--batch", batch.as_str()])?;
    Ok(())
}

/// Toggle floating and resize/center windows when promoting from tiled mode.
pub(crate) fn toggle_float() -> Result<()> {
    let window = active_window()?;
    if window.floating {
        dispatch(&["togglefloating"])?;
    } else {
        batch(&[
            "dispatch togglefloating",
            "dispatch resizeactive exact 75% 75%",
            "dispatch centerwindow 1",
        ])?;
    }

    Ok(())
}

/// Return the Hyprland event-socket path used by the focus daemon.
pub(crate) fn socket2_path() -> Result<PathBuf> {
    let signature = env::var("HYPRLAND_INSTANCE_SIGNATURE").map_err(|_| {
        io::Error::new(
            io::ErrorKind::NotFound,
            "HYPRLAND_INSTANCE_SIGNATURE is not set",
        )
    })?;

    Ok(paths::xdg_runtime_dir()?
        .join("hypr")
        .join(signature)
        .join(".socket2.sock"))
}

fn hyprctl_output(args: &[&str]) -> Result<Output> {
    let output = Command::new("hyprctl").args(args).output()?;
    if output.status.success() {
        return Ok(output);
    }

    let stderr = String::from_utf8_lossy(&output.stderr);
    let message = format!(
        "hyprctl {} failed: {}",
        args.join(" "),
        stderr.trim().if_empty("(no stderr)")
    );

    Err(io::Error::other(message).into())
}

trait IfEmpty {
    fn if_empty(self, fallback: &str) -> String;
}

impl IfEmpty for &str {
    fn if_empty(self, fallback: &str) -> String {
        if self.is_empty() {
            fallback.to_owned()
        } else {
            self.to_owned()
        }
    }
}
