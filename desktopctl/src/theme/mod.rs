#![allow(dead_code)]

use crate::paths;
use std::{
    env, io,
    path::{Path, PathBuf},
    process::Command,
};

pub mod json;
pub mod orchestrator;
pub mod resolve;
pub mod schema;
pub mod targets;

pub(crate) fn expand_user_path(path: &str) -> crate::Result<PathBuf> {
    if path == "~" {
        return Ok(paths::home_dir()?);
    }

    if let Some(rest) = path.strip_prefix("~/") {
        return Ok(paths::home_dir()?.join(rest));
    }

    Ok(PathBuf::from(path))
}

pub(crate) fn run_command(command: &[&str]) -> crate::Result<()> {
    if command.is_empty() {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "Command cannot be empty").into());
    }

    let output = Command::new(command[0]).args(&command[1..]).output();
    command_result(output, command[0])
}

pub(crate) fn run_owned_command(command: &[String]) -> crate::Result<()> {
    if command.is_empty() {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "Command cannot be empty").into());
    }

    let output = Command::new(&command[0]).args(&command[1..]).output();
    command_result(output, &command[0])
}

pub(crate) fn find_command(program: &str) -> Option<PathBuf> {
    if program.contains(std::path::MAIN_SEPARATOR) {
        let path = PathBuf::from(program);
        return is_executable(&path).then_some(path);
    }

    let path_var = env::var_os("PATH")?;
    env::split_paths(&path_var)
        .map(|dir| dir.join(program))
        .find(|candidate| is_executable(candidate))
}

fn is_executable(path: &Path) -> bool {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;

        match path.metadata() {
            Ok(metadata) => metadata.is_file() && metadata.permissions().mode() & 0o111 != 0,
            Err(_) => false,
        }
    }

    #[cfg(not(unix))]
    {
        path.is_file()
    }
}

fn command_result(output: io::Result<std::process::Output>, program: &str) -> crate::Result<()> {
    let output = match output {
        Ok(output) => output,
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            return Err(
                io::Error::new(io::ErrorKind::NotFound, format!("{program:?} not found")).into(),
            );
        }
        Err(error) => return Err(error.into()),
    };

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

    Err(io::Error::other(message).into())
}
