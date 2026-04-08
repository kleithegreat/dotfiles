use crate::paths;
use serde::Deserialize;
use std::{
    env, fs, io,
    path::PathBuf,
    process::{Command, Output},
    time::{SystemTime, UNIX_EPOCH},
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
    let signature = hyprland_signature();
    if let Some(signature) = signature.as_deref() {
        let runtime_path = runtime_socket2_path(signature)?;
        if runtime_path.exists() {
            return Ok(runtime_path);
        }

        let tmp_path = tmp_socket2_path(signature);
        if tmp_path.exists() {
            return Ok(tmp_path);
        }
    }

    if let Some(path) = discover_socket2_path()? {
        return Ok(path);
    }

    if let Some(signature) = signature {
        return Ok(runtime_socket2_path(&signature)?);
    }

    Err(io::Error::new(
        io::ErrorKind::NotFound,
        "unable to resolve Hyprland event socket path",
    )
    .into())
}

fn hyprland_signature() -> Option<String> {
    env::var("HYPRLAND_INSTANCE_SIGNATURE")
        .ok()
        .filter(|value| !value.is_empty())
}

fn runtime_socket2_path(signature: &str) -> io::Result<PathBuf> {
    Ok(paths::xdg_runtime_dir()?
        .join("hypr")
        .join(signature)
        .join(".socket2.sock"))
}

fn tmp_socket2_path(signature: &str) -> PathBuf {
    PathBuf::from("/tmp/hypr")
        .join(signature)
        .join(".socket2.sock")
}

fn discover_socket2_path() -> Result<Option<PathBuf>> {
    let mut candidates = Vec::new();
    candidates.extend(find_socket2_candidates(&paths::xdg_runtime_dir()?.join("hypr"))?);
    candidates.extend(find_socket2_candidates(&PathBuf::from("/tmp/hypr"))?);

    Ok(candidates
        .into_iter()
        .max_by_key(|(modified, _)| *modified)
        .map(|(_, path)| path))
}

fn find_socket2_candidates(root: &PathBuf) -> io::Result<Vec<(SystemTime, PathBuf)>> {
    let entries = match fs::read_dir(root) {
        Ok(entries) => entries,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(error) => return Err(error),
    };

    let mut candidates = Vec::new();
    for entry in entries {
        let entry = entry?;
        let path = entry.path().join(".socket2.sock");
        if !path.exists() {
            continue;
        }

        let modified = fs::metadata(&path)
            .and_then(|metadata| metadata.modified())
            .unwrap_or(UNIX_EPOCH);
        candidates.push((modified, path));
    }

    Ok(candidates)
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
