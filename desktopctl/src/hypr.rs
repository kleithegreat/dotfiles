#![allow(dead_code)]

use crate::paths;
use serde::Deserialize;
use std::{
    env,
    io,
    path::PathBuf,
    process::{Command, Output},
};

pub type Result<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;

#[derive(Debug, Clone, Deserialize)]
pub struct WindowInfo {
    #[serde(default)]
    pub class: String,
    #[serde(rename = "initialClass", default)]
    pub initial_class: String,
    #[serde(default)]
    pub title: String,
    #[serde(rename = "initialTitle", default)]
    pub initial_title: String,
    #[serde(default)]
    pub floating: bool,
}

/// Query Hyprland for the currently active window.
pub fn active_window() -> Result<WindowInfo> {
    let output = hyprctl_output(&["activewindow", "-j"])?;
    Ok(serde_json::from_slice(&output.stdout)?)
}

/// Run `hyprctl dispatch ...`.
pub fn dispatch(args: &[&str]) -> Result<()> {
    let mut command_args = Vec::with_capacity(args.len() + 1);
    command_args.push("dispatch");
    command_args.extend(args.iter().copied());
    hyprctl_output(&command_args)?;
    Ok(())
}

/// Run `hyprctl --batch ...`.
pub fn batch(commands: &[&str]) -> Result<()> {
    if commands.is_empty() {
        return Ok(());
    }

    let batch = commands.join(" ; ");
    hyprctl_output(&["--batch", batch.as_str()])?;
    Ok(())
}

/// Run `hyprctl keyword <key> <value>`.
pub fn keyword(key: &str, value: &str) -> Result<()> {
    hyprctl_output(&["keyword", key, value])?;
    Ok(())
}

/// Return the Hyprland event-socket path used by the focus daemon.
pub fn socket2_path() -> Result<PathBuf> {
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
